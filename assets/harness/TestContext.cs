using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;

namespace __HARNESS_NAME__
{
    public sealed class TestContext
    {
        private readonly TextWriter log;
        private readonly TestResult result;
        internal TestContext(Document document, string root, TestResult result, TextWriter log)
        { Document = document; RunDirectory = root; this.result = result; this.log = log; }
        public Document Document { get; private set; }
        public Database Database { get { return Document.Database; } }
        public string RunDirectory { get; private set; }
        public string RunId { get { return result.RunId; } }
        public void Check(bool condition, string description)
        {
            result.AssertionCount++;
            log.WriteLine((condition ? "PASS " : "FAIL ") + description);
            if (!condition) throw new InvalidOperationException("Assertion failed: " + description);
        }
        public void Log(string message) { log.WriteLine(message); }
        public string InputPath(string name)
        {
            if (string.IsNullOrWhiteSpace(name) || name != Path.GetFileName(name)) throw new ArgumentException("Use a fixture filename.");
            string path = Path.Combine(RunDirectory, "inputs", name);
            if (!File.Exists(path)) throw new FileNotFoundException("Fixture is missing.", path);
            return path;
        }
        public void RecordAssembly(Assembly assembly)
        {
            var item = new AssemblyEvidence { Name = assembly.GetName().Name, Path = assembly.Location, Sha256 = JsonFiles.Hash(assembly.Location) };
            result.PluginAssemblies.Add(item);
            Log("ASSEMBLY " + item.Name + " " + item.Path + " SHA256=" + item.Sha256);
        }
        // Call ONLY from the modal document command, after all service transactions close.
        // Prompt arguments must be complete; interactive UI commands need a separate UI test.
        public void ExecuteCommand(string globalName, params object[] arguments)
        {
            if (Database.TransactionManager.NumberOfActiveTransactions != 0) throw new InvalidOperationException("Close transactions before Editor.Command.");
            bool ended = false, failed = false, cancelled = false;
            CommandEventHandler onEnd = (sender, e) => { if (e.GlobalCommandName.Equals(globalName, StringComparison.OrdinalIgnoreCase)) ended = true; };
            CommandEventHandler onFail = (sender, e) => { if (e.GlobalCommandName.Equals(globalName, StringComparison.OrdinalIgnoreCase)) failed = true; };
            CommandEventHandler onCancel = (sender, e) => { if (e.GlobalCommandName.Equals(globalName, StringComparison.OrdinalIgnoreCase)) cancelled = true; };
            Document.CommandEnded += onEnd; Document.CommandFailed += onFail; Document.CommandCancelled += onCancel;
            try
            {
                Log("COMMAND BEGIN " + globalName);
                var tokens = new object[arguments.Length + 1]; tokens[0] = globalName;
                Array.Copy(arguments, 0, tokens, 1, arguments.Length);
                Document.Editor.Command(tokens);
                Check(ended && !failed && !cancelled, "Real command completed: " + globalName);
                result.CommandsCompleted.Add(globalName);
            }
            finally { Document.CommandEnded -= onEnd; Document.CommandFailed -= onFail; Document.CommandCancelled -= onCancel; }
        }
        public void SaveEvidenceDrawing(string name)
        {
            if (string.IsNullOrWhiteSpace(name) || name != Path.GetFileName(name) || Path.GetExtension(name) != ".dwg") throw new ArgumentException("Use a .dwg filename.");
            string path = Path.Combine(RunDirectory, name);
            if (File.Exists(path)) throw new IOException("Evidence already exists.");
            // Save a clone; never SaveAs the active input drawing.
            using (Database copy = Database.Wblock()) copy.SaveAs(path, DwgVersion.Current);
            Log("DWG EVIDENCE " + path);
        }
        internal static string[] ModelHandles(Database database)
        {
            using (Transaction tr = database.TransactionManager.StartOpenCloseTransaction())
            {
                var table = (BlockTable)tr.GetObject(database.BlockTableId, OpenMode.ForRead);
                var model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                return model.Cast<ObjectId>().Select(id => id.Handle.ToString()).OrderBy(x => x, StringComparer.Ordinal).ToArray();
            }
        }
    }
    [DataContract] internal sealed class RunConfiguration
    {
        [DataMember] public int SchemaVersion { get; set; }
        [DataMember] public string RunId { get; set; }
        [DataMember] public string DrawingPath { get; set; }
        [DataMember] public string InputKind { get; set; }
        [DataMember] public string ExpectedAcadVersion { get; set; }
        [DataMember] public string Host { get; set; }
        [DataMember] public string TestAssemblyPath { get; set; }
        [DataMember] public string TestAssemblySha256 { get; set; }
    }
    [DataContract] public sealed class AssemblyEvidence
    {
        [DataMember] public string Name { get; set; }
        [DataMember] public string Path { get; set; }
        [DataMember] public string Sha256 { get; set; }
    }
    [DataContract] internal sealed class TestResult
    {
        [DataMember] public int SchemaVersion { get; set; }
        [DataMember] public string RunId { get; set; }
        [DataMember] public int ProcessId { get; set; }
        [DataMember] public string Scope { get; set; }
        [DataMember] public string Host { get; set; }
        [DataMember] public string AcadVersion { get; set; }
        [DataMember] public string HostBuild { get; set; }
        [DataMember] public string DrawingPath { get; set; }
        [DataMember] public string ActualDocumentName { get; set; }
        [DataMember] public string TestAssemblyPath { get; set; }
        [DataMember] public string TestAssemblySha256 { get; set; }
        [DataMember] public bool Complete { get; set; }
        [DataMember] public bool Success { get; set; }
        [DataMember] public bool ServiceTransactionAborted { get; set; }
        [DataMember] public bool ModelHandleSetRestored { get; set; }
        [DataMember] public bool ClosedWithoutSaving { get; set; }
        [DataMember] public bool DiscardOnProcessExitRequested { get; set; }
        [DataMember] public int AssertionCount { get; set; }
        [DataMember] public int ScenarioAssertionCount { get; set; }
        [DataMember] public List<string> Failures { get; set; } = new List<string>();
        [DataMember] public List<string> CommandsCompleted { get; set; } = new List<string>();
        [DataMember] public List<AssemblyEvidence> PluginAssemblies { get; set; } = new List<AssemblyEvidence>();
    }
    internal static class JsonFiles
    {
        internal static T Read<T>(string path)
        { using (var stream = File.OpenRead(path)) return (T)new DataContractJsonSerializer(typeof(T)).ReadObject(stream); }
        internal static void Write<T>(string path, T value)
        {
            using (var stream = File.Create(path + ".tmp")) new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value);
            File.Move(path + ".tmp", path);
        }
        internal static string Hash(string path)
        { using (var stream = File.OpenRead(path)) using (var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", ""); }
    }
}

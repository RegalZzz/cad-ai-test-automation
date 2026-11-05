using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Runtime;
using Application = Autodesk.AutoCAD.ApplicationServices.Core.Application;

[assembly: ExtensionApplication(typeof(__HARNESS_NAME__.CadTestApplication))]
[assembly: CommandClass(typeof(__HARNESS_NAME__.CadTestApplication))]
[assembly: CommandClass(typeof(__HARNESS_NAME__.SmokeCommands))]

namespace __HARNESS_NAME__
{
    public sealed class CadTestApplication : IExtensionApplication
    {
        private static string root;
        private static RunConfiguration config;
        private static TestResult result;
        private static Document ownedDocument;
        private static StreamWriter log;
        public void Initialize()
        {
            string directory = Environment.GetEnvironmentVariable("CAD_TEST_RUN_DIRECTORY");
            string id = Environment.GetEnvironmentVariable("CAD_TEST_RUN_ID");
            if (string.IsNullOrEmpty(directory) || string.IsNullOrEmpty(id)) return;
            root = Path.GetFullPath(directory);
            try
            {
                config = JsonFiles.Read<RunConfiguration>(Path.Combine(root, "run.json"));
                if (config.SchemaVersion != 1 || config.RunId != id) throw new InvalidOperationException("Run identity mismatch.");
                string assembly = GetType().Assembly.Location;
                if (!string.Equals(assembly, config.TestAssemblyPath, StringComparison.OrdinalIgnoreCase) || JsonFiles.Hash(assembly) != config.TestAssemblySha256)
                    throw new InvalidOperationException("Runner location/hash mismatch.");
                using (var signal = new FileStream(Path.Combine(root, "started.txt"), FileMode.CreateNew, FileAccess.Write))
                using (var writer = new StreamWriter(signal)) writer.WriteLine("NETLOAD " + assembly + " PID=" + Process.GetCurrentProcess().Id);
            }
            catch (System.Exception e) { File.WriteAllText(Path.Combine(root, "startup-error.txt"), e.ToString()); config = null; }
        }
        public void Terminate() { }

        [CommandMethod("CADTEST_RUN", CommandFlags.Modal)]
        public void Run()
        {
            if (config == null || result != null) return;
            string exe = Process.GetCurrentProcess().ProcessName;
            result = new TestResult {
                SchemaVersion = 1, RunId = config.RunId, ProcessId = Process.GetCurrentProcess().Id,
                Scope = TestScenario.Scope, Host = exe.Equals("accoreconsole", StringComparison.OrdinalIgnoreCase) ? "CoreConsole" : "Desktop",
                AcadVersion = Convert.ToString(Application.GetSystemVariable("ACADVER")),
                HostBuild = FileVersionInfo.GetVersionInfo(Process.GetCurrentProcess().MainModule.FileName).FileVersion,
                DrawingPath = config.DrawingPath, TestAssemblyPath = GetType().Assembly.Location,
                TestAssemblySha256 = JsonFiles.Hash(GetType().Assembly.Location)
            };
            log = new StreamWriter(Path.Combine(root, "assertions.log"), false, new UTF8Encoding(false)) { AutoFlush = true };
            try
            {
                if (Regex.Match(result.AcadVersion, @"^\d+\.\d+").Value != config.ExpectedAcadVersion)
                    throw new InvalidOperationException("Wrong AutoCAD API version: " + result.AcadVersion);
                if (result.Host != config.Host) throw new InvalidOperationException("Wrong CAD host.");
                Document document = Application.DocumentManager.MdiActiveDocument;
                if (document == null || Application.DocumentManager.Count != 1) throw new InvalidOperationException("Expected one dedicated test document.");
                result.ActualDocumentName = document.Name;
                if (config.InputKind == "Drawing" && !string.Equals(Path.GetFullPath(document.Name), Path.GetFullPath(config.DrawingPath), StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Active document is not this run's copy.");
                if (config.InputKind == "Template" && Convert.ToInt32(Application.GetSystemVariable("DWGTITLED")) != 0)
                    throw new InvalidOperationException("Template test requires a new untitled drawing.");
                ownedDocument = document;
                var context = new TestContext(document, root, result, log);
                context.Log("HOST " + result.Host + " " + result.AcadVersion + " BUILD " + result.HostBuild);
                context.Log("SCOPE " + result.Scope);
                context.RecordAssembly(GetType().Assembly);
                string[] baseline = TestContext.ModelHandles(document.Database);
                using (Transaction outer = document.Database.TransactionManager.StartTransaction())
                {
                    try { TestScenario.RunServices(context); }
                    finally { outer.Abort(); result.ServiceTransactionAborted = true; }
                }
                result.ScenarioAssertionCount = result.AssertionCount;
                result.ModelHandleSetRestored = baseline.SequenceEqual(TestContext.ModelHandles(document.Database));
                context.Check(result.ModelHandleSetRestored, "ModelSpace handles restored after service transaction abort (not a full database equality check)");
                // Real command dispatch occurs AFTER the service transaction. Command changes are discarded on close.
                int beforeCommands = result.AssertionCount;
                TestScenario.RunCommands(context);
                result.ScenarioAssertionCount += result.AssertionCount - beforeCommands;
            }
            catch (System.Exception e) { result.Failures.Add(e.ToString()); log.WriteLine("FAIL " + e); }
            finally { log.WriteLine("Tests finished; waiting for session cleanup command CADTEST_FINISH."); }
        }

        [CommandMethod("CADTEST_FINISH", CommandFlags.Session)]
        public void Finish()
        {
            if (result == null || result.Complete) return;
            try
            {
                if (ownedDocument != null) {
#if CAD_CORE_CONSOLE
                    // Core Console has no AcMgd CloseAndDiscard extension. The SCR issues QUIT/N.
                    // External validation must observe process exit + unchanged source/copy hashes.
                    result.DiscardOnProcessExitRequested = true;
#else
                    ownedDocument.CloseAndDiscard(); result.ClosedWithoutSaving = true;
#endif
                }
                else result.Failures.Add("No owned test document; nothing was closed.");
            }
            catch (System.Exception e) { result.Failures.Add("CloseAndDiscard: " + e); }
            result.Complete = true;
            result.Success = result.Failures.Count == 0 && result.ScenarioAssertionCount > 0 && result.ServiceTransactionAborted && result.ModelHandleSetRestored && (result.ClosedWithoutSaving || result.DiscardOnProcessExitRequested);
            log.WriteLine(result.Success ? "PASS suite" : "FAIL suite"); log.Dispose();
            JsonFiles.Write(Path.Combine(root, "result.json"), result);
            if (result.Host == "Desktop" && Application.DocumentManager.Count == 0) Application.Idle += QuitWhenIdle;
        }
        private static void QuitWhenIdle(object sender, EventArgs args)
        {
            Application.Idle -= QuitWhenIdle;
            if (Application.DocumentManager.Count == 0) Application.Quit();
        }
    }
}

using System;
using System.Linq;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using Application = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace __HARNESS_NAME__
{
    public static class TestScenario
    {
        // This suite proves harness/API/fixture-command behavior only. Replace with actual business scope.
        public const string Scope = "api-smoke + fixture-command-smoke; no business plugin tested";
        public static void RunServices(TestContext context)
        {
            using (Transaction tr = context.Database.TransactionManager.StartTransaction())
            {
                var table = (BlockTable)tr.GetObject(context.Database.BlockTableId, OpenMode.ForRead);
                var model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForWrite);
                var line = new Line(new Point3d(10, 20, 0), new Point3d(110, 20, 0));
                ObjectId id = model.AppendEntity(line); tr.AddNewlyCreatedDBObject(line, true);
                context.Check(Math.Abs(line.Length - 100) < 1e-8, "Created line length is 100 drawing units");
                tr.Commit();
                using (Transaction read = context.Database.TransactionManager.StartOpenCloseTransaction())
                {
                    var persisted = (Line)read.GetObject(id, OpenMode.ForRead);
                    context.Check(persisted.StartPoint.DistanceTo(new Point3d(10, 20, 0)) < 1e-8, "Re-read committed nested transaction: start point");
                    context.Check(persisted.EndPoint.DistanceTo(new Point3d(110, 20, 0)) < 1e-8, "Re-read committed nested transaction: end point");
                }
            }
        }
        public static void RunCommands(TestContext context)
        {
            // SmokeCommands is a test fixture, NOT the user's production command.
            context.SaveEvidenceDrawing("before-commands.dwg");
            int before = TestContext.ModelHandles(context.Database).Length;
            context.ExecuteCommand("CADTEST_PROBE");
            context.Check(TestContext.ModelHandles(context.Database).Length == before + 1, "Fixture command added exactly one ModelSpace entity");
            using (Transaction tr = context.Database.TransactionManager.StartOpenCloseTransaction())
            {
                var table = (BlockTable)tr.GetObject(context.Database.BlockTableId, OpenMode.ForRead);
                var model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                var lines = model.Cast<ObjectId>().Select(id => tr.GetObject(id, OpenMode.ForRead)).OfType<Line>()
                    .Where(x => x.StartPoint.DistanceTo(new Point3d(1234, 5678, 0)) < 1e-8 && x.EndPoint.DistanceTo(new Point3d(1284, 5678, 0)) < 1e-8).ToArray();
                context.Check(lines.Length == 1, "Re-read fixture command geometry: known endpoints, length 50");
            }
            context.SaveEvidenceDrawing("after-commands.dwg");
        }
    }
    public sealed class SmokeCommands
    {
        [CommandMethod("CADTEST_PROBE", CommandFlags.Modal)]
        public void Probe()
        {
            Database database = Application.DocumentManager.MdiActiveDocument.Database;
            using (Transaction tr = database.TransactionManager.StartTransaction())
            {
                var table = (BlockTable)tr.GetObject(database.BlockTableId, OpenMode.ForRead);
                var model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForWrite);
                var line = new Line(new Point3d(1234, 5678, 0), new Point3d(1284, 5678, 0));
                model.AppendEntity(line); tr.AddNewlyCreatedDBObject(line, true); tr.Commit();
            }
        }
    }
}

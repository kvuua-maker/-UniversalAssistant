import importlib.util, json, pathlib, tempfile, unittest

MODULE_PATH = pathlib.Path(__file__).with_name("live_diagnostics.py")
SPEC = importlib.util.spec_from_file_location("live_diagnostics", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MODULE)

class Args:
    command = "latest"; feature = None; build = None; session_id = None; timestamp = None

class ReaderTests(unittest.TestCase):
    def test_latest_feature_build_session_failures_and_since_are_read_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            first = {"sessionID":"one", "feature":"voice", "build":9, "startedAt":"2026-09-04T20:00:00Z", "result":"FAILURE", "schema":1, "events":[]}
            second = {"sessionID":"two", "feature":"voice", "build":10, "startedAt":"2026-09-04T21:00:00Z", "result":"UNKNOWN", "schema":1, "events":[]}
            (root / "one.json").write_text(json.dumps(first)); (root / "two.json").write_text(json.dumps(second))
            before = {p.name:p.read_bytes() for p in root.iterdir()}
            values = MODULE.records(root)
            args = Args(); self.assertEqual(MODULE.select(values, args)[0]["sessionID"], "two")
            args.feature="voice"; args.build=9; self.assertEqual(MODULE.select(values,args)[0]["sessionID"], "one")
            args.command="session"; args.session_id="one"; self.assertEqual(len(MODULE.select(values,args)),1)
            args.command="failures"; self.assertEqual([v["sessionID"] for v in MODULE.select(values,args)], ["one"])
            args.command="since"; args.timestamp="2026-09-04T20:30:00Z"; self.assertEqual([v["sessionID"] for v in MODULE.select(values,args)], ["two"])
            self.assertEqual(before, {p.name:p.read_bytes() for p in root.iterdir()})

    def test_bootstrap_failure_is_visible_but_marked_pre_attestation_unverified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary); (root / "sessions").mkdir(); (root / "bootstrap").mkdir()
            report = {"reportID":"bootstrap-one", "build":12, "startedAt":"2026-09-05T00:00:00Z", "schema":1,
                      "failureStage":"attest_key_invoked", "events":[]}
            path = root / "bootstrap" / "bootstrap-one.json"; path.write_text(json.dumps(report)); before = path.read_bytes()
            values = MODULE.records(root)
            self.assertEqual(values[0]["feature"], "app-attest-bootstrap")
            self.assertEqual(values[0]["authentication"], "pre-attestation-unverified")
            args = Args(); args.build = 12
            self.assertEqual(MODULE.select(values, args)[0]["sessionID"], "bootstrap-one")
            self.assertEqual(path.read_bytes(), before)

if __name__ == "__main__": unittest.main()

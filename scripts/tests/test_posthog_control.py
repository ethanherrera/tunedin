import copy
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "posthog_control", ROOT / "scripts" / "posthog_control.py"
)
posthog_control = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(posthog_control)


class PostHogControlTests(unittest.TestCase):
    def setUp(self):
        self.manifest = posthog_control.load_manifest()

    def test_tracked_staging_contract_matches_swift_allow_list(self):
        posthog_control.validate_manifest(self.manifest)

    def test_refuses_any_other_project(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["project"]["id"] = 507315
        with self.assertRaises(posthog_control.PostHogContractError):
            posthog_control.validate_manifest(manifest)

    def test_refuses_relaxed_privacy_settings(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["privacy_settings"]["session_recording_opt_in"] = True
        with self.assertRaises(posthog_control.PostHogContractError):
            posthog_control.validate_manifest(manifest)

    def test_project_drift_names_only_safe_fixed_fields(self):
        hosted = {
            "id": 507318,
            "name": "tunedIn Staging",
            **self.manifest["privacy_settings"],
        }
        hosted["autocapture_opt_out"] = False
        self.assertEqual(
            posthog_control.project_drift(self.manifest, hosted),
            ["privacy_settings.autocapture_opt_out"],
        )


if __name__ == "__main__":
    unittest.main()

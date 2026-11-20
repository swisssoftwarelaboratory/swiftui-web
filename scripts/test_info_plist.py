#!/usr/bin/env python3
"""scripts/info_plist.py reads an app's Info dictionary as Xcode builds it (new-website#663).

    python3 -m unittest discover -s scripts -p 'test_*.py'"""
import tempfile, unittest
from pathlib import Path

from info_plist import info_dictionary, parse_openstep

PROJECT = """// !$*UTF8*$!
{
	archiveVersion = 1;
	objects = {
		P1 /* Project object */ = {
			isa = PBXProject;
			buildConfigurationList = PL /* Build configuration list for PBXProject */;
			targets = ( T1 /* App */, T2 /* Widgets */, );
		};
		PL = { isa = XCConfigurationList; buildConfigurations = ( PD, PR, ); defaultConfigurationName = Release; };
		PD = { isa = XCBuildConfiguration; buildSettings = { MARKETING_VERSION = 0.9; }; name = Debug; };
		PR = { isa = XCBuildConfiguration; buildSettings = { MARKETING_VERSION = 1.0; }; name = Release; };
		T1 /* App */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = TL;
			name = App;
			productType = "com.apple.product-type.application";
		};
		T2 /* Widgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = TL;
			name = Widgets;
			productType = "com.apple.product-type.app-extension";
		};
		TL = { isa = XCConfigurationList; buildConfigurations = ( TD, TR, ); };
		TD = { isa = XCBuildConfiguration; buildSettings = { INFOPLIST_KEY_UIUserInterfaceStyle = Dark; }; name = Debug; };
		TR = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "App-Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = "My \\"App\\"";
				INFOPLIST_KEY_UIUserInterfaceStyle = Light;
				INFOPLIST_KEY_NSSupportsLiveActivities = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft";
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
			};
			name = Release;
		};
	};
	rootObject = P1 /* Project object */;
}
"""

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>NSCameraUsageDescription</key><string>Photos of $(PRODUCT_NAME)</string>
	<key>CFBundleDisplayName</key><string>From the file</string>
</dict></plist>
"""


class InfoPlistTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name) / "app"
        (root / "App.xcodeproj").mkdir(parents=True)
        (root / "App.xcodeproj" / "project.pbxproj").write_text(PROJECT)
        (root / "App-Info.plist").write_text(PLIST)
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_generated_keys_and_file_merge_as_xcode_builds_them(self):
        info = info_dictionary(self.root)
        self.assertEqual(info["UIUserInterfaceStyle"], "Light")
        self.assertIs(info["NSSupportsLiveActivities"], True)
        self.assertEqual(info["UISupportedInterfaceOrientations"], ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft"])
        self.assertNotIn("UILaunchScreen_Generation", info)
        self.assertEqual(info["CFBundleIdentifier"], "com.example.app")
        self.assertEqual(info["CFBundleName"], "App")
        self.assertEqual(info["CFBundleShortVersionString"], "1.0")   # the project's setting, under the target's
        self.assertEqual(info["NSCameraUsageDescription"], "Photos of App")
        self.assertEqual(info["CFBundleDisplayName"], "From the file")   # the file's own key wins

    def test_debug_reads_the_debug_configuration(self):
        info = info_dictionary(self.root, configuration="Debug")
        self.assertEqual(info["UIUserInterfaceStyle"], "Dark")
        self.assertEqual(info["CFBundleShortVersionString"], "0.9")

    def test_no_project_is_an_empty_dictionary(self):
        with tempfile.TemporaryDirectory() as empty:
            self.assertEqual(info_dictionary(empty), {})

    def test_quoted_strings_and_comments(self):
        parsed = parse_openstep('{ a = "x \\"y\\""; /* c */ b = ( 1, two, ); // end\n}')
        self.assertEqual(parsed, {"a": 'x "y"', "b": ["1", "two"]})


if __name__ == "__main__":
    unittest.main()

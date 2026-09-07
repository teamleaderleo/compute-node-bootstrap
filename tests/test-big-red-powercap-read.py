#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class PowercapReadTest(unittest.TestCase):
    def test_emits_only_allowlisted_named_domains(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for directory, name, energy in (
                ("one", "package-0", 20),
                ("two", "psys", 30),
                ("three", "core", 10),
                ("duplicate", "package-0", 40),
            ):
                path = root / directory
                path.mkdir()
                (path / "name").write_text(name)
                (path / "energy_uj").write_text(str(energy))
                (path / "max_energy_range_uj").write_text("100")
            helper = Path(__file__).parents[1] / "scripts" / "big-red-powercap-read"
            environment = {**os.environ, "POWER_CAP_SYSFS_ROOT": str(root)}
            result = subprocess.run([helper], check=True, capture_output=True, text=True, env=environment)
        document = json.loads(result.stdout)
        self.assertEqual({item["name"] for item in document}, {"psys", "package-0"})
        self.assertEqual(len(document), 2)
        self.assertNotIn("path", result.stdout)


if __name__ == "__main__":
    unittest.main()

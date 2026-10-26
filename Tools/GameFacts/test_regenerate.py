import json
from pathlib import Path
import tempfile
import unittest

from regenerate import canonical_extraction, digest


class ExtractionProvenanceTests(unittest.TestCase):
    def test_object_order_and_whitespace_do_not_change_provenance(self):
        first = '{"steps":[{"output":{"b":2,"a":1},"name":"proof"}],"unicode":"\\u00e9"}'
        second = '{ "unicode": "é", "steps": [ { "name": "proof", "output": {"a": 1, "b": 2} } ] }\n'
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            outputs = []
            for index, source in enumerate([first, second]):
                raw, output = root / f"{index}.raw.json", root / f"{index}.json"
                raw.write_text(source)
                value = canonical_extraction(raw, output)
                self.assertEqual(raw.read_text(), source)
                self.assertEqual(value, json.loads(output.read_text()))
                outputs.append(output)
            self.assertEqual(digest(outputs[0]), digest(outputs[1]))

    def test_array_order_and_changed_values_remain_distinct(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            hashes = []
            for index, source in enumerate(['{"steps":[1,2]}', '{"steps":[2,1]}', '{"steps":[1,3]}']):
                raw, output = root / f"{index}.raw.json", root / f"{index}.json"
                raw.write_text(source)
                canonical_extraction(raw, output)
                self.assertEqual(json.loads(output.read_text()), json.loads(source))
                hashes.append(digest(output))
            self.assertEqual(len(set(hashes)), 3)


if __name__ == "__main__":
    unittest.main()

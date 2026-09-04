"""Regression checks for observer analysis, not shader-quality approval."""
import unittest
import numpy as np


class TraceAnalysisTests(unittest.TestCase):
    def test_float32_texel_rounding_before_floor(self):
        # Promoting the stored UV first can choose the previous texel.
        # Recorded at frame 4, receiver 57, step 9: float bits 0x3f466666.
        uv = np.float32(.775)
        shader = int(np.floor(uv*np.float32(1280)))
        promoted = int(np.floor(float(uv)*1280))
        self.assertEqual(shader, 992)
        self.assertEqual(promoted, 991)

    def test_interval_can_hit_while_point_is_in_front(self):
        lo, hi, depth, bias, thickness, point = 126.74, 131.37, 130.03, .1389, 8.75, 129.01
        self.assertTrue(hi > depth+bias and lo < depth+thickness)
        self.assertLess(point, depth+bias)

    def test_interval_can_hit_while_point_is_behind_volume(self):
        lo, hi, depth, bias, thickness, point = 136.65, 141.44, 129.93, .1389, 8.75, 139.0
        self.assertTrue(hi > depth+bias and lo < depth+thickness)
        self.assertGreater(point, depth+thickness)

    def test_donor_falloff_from_earliest_hit(self):
        times = np.array([.2, .3, .4])
        visibility = min((times*times).tolist())**3
        self.assertAlmostEqual(visibility, .2**6)


if __name__ == '__main__':
    unittest.main()

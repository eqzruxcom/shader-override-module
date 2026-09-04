"""Small analytic invariants for the diagnostic, independent of GPU results."""
import unittest
import numpy as np
from analyze_rebirth_pixel_truth import INF, scene, truth


class GeometryTests(unittest.TestCase):
    def test_plane(self):
        distance, on_box = scene(np.array([0., 0., 0.]), np.array([0., 0., 1.]), np.array([100., 10., 130.]))
        self.assertAlmostEqual(float(distance), 160.)
        self.assertFalse(on_box)

    def test_front_face_and_inside_exit(self):
        box = np.array([0., 10., 130.])
        origin = np.array([[0., 10., 0.], [0., 10., 130.]])
        rays = np.array([[0., 0., 1.], [1., 0., 0.]])
        distance, on_box = scene(origin, rays, box)
        np.testing.assert_allclose(distance, [122., 8.])
        self.assertTrue(on_box.all())

    def test_parallel_and_behind(self):
        distance, _ = scene(np.array([0., 0., 0.]), np.array([0., 0., -1.]), np.array([100., 10., 130.]))
        self.assertEqual(float(distance), INF)

    def test_shadow_and_clear_ray(self):
        point = np.array([[0., 0., 160.]])
        camera, rotation = np.zeros(3), np.eye(3)
        shadow, _ = truth(point, camera, rotation, np.array([20., 10., 130.]))
        clear, _ = truth(point, camera, rotation, np.array([-20., 10., 130.]))
        self.assertTrue(shadow[0])
        self.assertFalse(clear[0])

    def test_broadcast_matches_scalar(self):
        rays = np.array([[.1, .05, 1.], [-.3, -.1, 1.], [0., 0., -1.]])
        box = np.array([20., 10., 130.])
        vector, _ = scene(np.zeros(3), rays, box)
        scalar = [float(scene(np.zeros(3), ray, box)[0]) for ray in rays]
        np.testing.assert_array_equal(vector, scalar)


if __name__ == '__main__':
    unittest.main()

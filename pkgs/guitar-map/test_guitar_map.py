import ctypes as C
import os
import unittest

from guitar_map import SDL, candidates, mapping_string, nix_snippet


class CaptureTests(unittest.TestCase):
    def test_button_hat_and_noise(self):
        rest = ((0, 0), (0,), (200,))
        self.assertEqual(candidates(rest, ((0, 1), (3,), (800,)), "a", 12000),
                         ["b1", "h0.1", "h0.2"])

    def test_axis_direction_and_rest(self):
        for rest, active, target, expected in [
            (-32768, 32767, "rightx", "a0"),
            (32767, -32768, "rightx", "a0~"),
            (0, 30000, "righty", "+a0"),
            (0, -30000, "righty", "-a0"),
            (0, -30000, "a", "-a0"),
            (0, 30000, "leftx", "a0"),
        ]:
            with self.subTest(rest=rest, target=target):
                self.assertEqual(candidates(((), (), (rest,)), ((), (), (active,)),
                                            target, 12000), [expected])

    def test_held_button_is_not_new_input(self):
        self.assertEqual(candidates(((1,), (), ()), ((1,), (), ()), "a", 12000), [])

    def test_output_escapes_nix_and_mapping_delimiters(self):
        mapping = mapping_string("0" * 32, 'Guitar,\n${oops}"', {"a": "b0"})
        self.assertNotIn("\n", mapping)
        self.assertIn(r'\${oops}\"', nix_snippet(mapping))
        self.assertIn("lib.mkAfter", nix_snippet(mapping))


@unittest.skipUnless(os.environ.get("GUITAR_MAP_SDL_LIBRARY"), "set SDL library for virtual-controller test")
class VirtualControllerTests(unittest.TestCase):
    def test_identical_guitars_and_reconnect(self):
        sdl = SDL()
        lib = sdl.lib
        lib.SDL_JoystickAttachVirtual.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int]
        lib.SDL_JoystickAttachVirtual.restype = C.c_int
        lib.SDL_JoystickDetachVirtual.argtypes = [C.c_int]
        lib.SDL_JoystickSetVirtualButton.argtypes = [C.c_void_p, C.c_int, C.c_int]
        joys, controllers, instances = [], [], []
        try:
            for _ in range(2):
                index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
                self.assertGreaterEqual(index, 0, sdl.error())
                joy = sdl.JoystickOpen(index)
                joys.append(joy)
                instances.append(sdl.JoystickInstanceID(joy))
            guid = bytes(sdl.JoystickGetGUID(joys[0]).data).hex()
            self.assertEqual(guid, bytes(sdl.JoystickGetGUID(joys[1]).data).hex())
            self.assertNotEqual(*instances)
            mapping = mapping_string(guid, "Identical guitar", {"a": "b0"})
            self.assertGreaterEqual(sdl.GameControllerAddMapping(mapping.encode()), 0)
            for instance in instances:
                controller = sdl.GameControllerOpen(sdl.device_index(instance))
                self.assertTrue(controller, sdl.error())
                controllers.append(controller)
            for active in (0, 1):
                for i, joy in enumerate(joys):
                    lib.SDL_JoystickSetVirtualButton(joy, 0, int(i == active))
                sdl.snapshot(joys[0])
                self.assertEqual([sdl.GameControllerGetButton(c, 0) for c in controllers],
                                 [int(i == active) for i in range(2)])
            previous_index = sdl.device_index(instances[1])
            lib.SDL_JoystickDetachVirtual(sdl.device_index(instances[0]))
            self.assertLess(sdl.device_index(instances[1]), previous_index)
            with self.assertRaisesRegex(RuntimeError, "disconnected"):
                sdl.device_index(instances[0])
            # Reattaching the same model gets a new instance but the same mapping.
            index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
            joy = sdl.JoystickOpen(index)
            joys.append(joy)
            instance = sdl.JoystickInstanceID(joy)
            self.assertNotIn(instance, instances)
            instances.append(instance)
            self.assertEqual(guid, bytes(sdl.JoystickGetGUID(joy).data).hex())
            controller = sdl.GameControllerOpen(index)
            self.assertTrue(controller, sdl.error())
            controllers.append(controller)
            lib.SDL_JoystickSetVirtualButton(joy, 0, 1)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 0), 1)
        finally:
            for controller in controllers:
                sdl.GameControllerClose(controller)
            for joy in joys:
                sdl.JoystickClose(joy)
            for instance in reversed(instances):
                try:
                    index = sdl.device_index(instance)
                except RuntimeError:
                    continue
                lib.SDL_JoystickDetachVirtual(index)
            sdl.Quit()

    def test_real_sdl_mapping_and_remapping(self):
        sdl = SDL()
        lib = sdl.lib
        lib.SDL_JoystickAttachVirtual.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int]
        lib.SDL_JoystickAttachVirtual.restype = C.c_int
        lib.SDL_JoystickDetachVirtual.argtypes = [C.c_int]
        for name in ("Button", "Axis", "Hat"):
            fn = getattr(lib, "SDL_JoystickSetVirtual" + name)
            fn.argtypes = [C.c_void_p, C.c_int, C.c_int]
            fn.restype = C.c_int
        index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
        self.assertGreaterEqual(index, 0, sdl.error())
        joy = sdl.JoystickOpen(index)
        controller = None
        try:
            guid = bytes(sdl.JoystickGetGUID(joy).data).hex()
            bindings = {"a": "b0", "start": "b11", "rightshoulder": "b8",
                        "dpup": "h0.1", "rightx": "a0~", "righty": "+a1",
                        "lefttrigger": "a2", "leftx": "a3"}
            self.assertGreaterEqual(sdl.GameControllerAddMapping(
                mapping_string(guid, "Test guitar", bindings).encode()), 0)
            controller = sdl.GameControllerOpen(index)
            self.assertTrue(controller, sdl.error())
            lib.SDL_JoystickSetVirtualButton(joy, 8, 1)
            lib.SDL_JoystickSetVirtualButton(joy, 11, 1)
            lib.SDL_JoystickSetVirtualHat(joy, 0, 1)
            lib.SDL_JoystickSetVirtualAxis(joy, 0, -32768)
            lib.SDL_JoystickSetVirtualAxis(joy, 1, 32767)
            lib.SDL_JoystickSetVirtualAxis(joy, 2, 32767)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 10), 1)  # RB
            self.assertEqual(sdl.GameControllerGetButton(controller, 6), 1)  # Start
            self.assertEqual(sdl.GameControllerGetButton(controller, 11), 1)  # D-pad up
            self.assertEqual(sdl.GameControllerGetAxis(controller, 2), 32767)
            self.assertEqual(sdl.GameControllerGetAxis(controller, 3), 32767)
            self.assertEqual(sdl.GameControllerGetAxis(controller, 4), 32767)
            sdl.GameControllerClose(controller)
            controller = None
            bindings["rightshoulder"] = "b9"
            sdl.GameControllerAddMapping(mapping_string(guid, "Test guitar", bindings).encode())
            controller = sdl.GameControllerOpen(index)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 10), 0)
        finally:
            if controller:
                sdl.GameControllerClose(controller)
            sdl.JoystickClose(joy)
            lib.SDL_JoystickDetachVirtual(index)
            sdl.Quit()


if __name__ == "__main__":
    unittest.main()

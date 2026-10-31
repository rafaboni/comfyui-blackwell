"""Test de la autenticacion por token de las rutas /rb_tools/*.

Corre sin instalar nada:
    python3 comfyui-kb-tools/test_auth.py

Simula `server` (PromptServer) y `aiohttp.web` en sys.modules para poder
importar el custom node sin ComfyUI ni aiohttp instalados.
"""

import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_PATH = os.path.join(HERE, "__init__.py")


def install_stubs():
    class FakeRoutes:
        def __init__(self):
            self.registered = []

        def get(self, path):
            def decorator(fn):
                self.registered.append(("GET", path))
                return fn
            return decorator

        def post(self, path):
            def decorator(fn):
                self.registered.append(("POST", path))
                return fn
            return decorator

    class FakeApp:
        def __init__(self):
            self.middlewares = []

    class FakePromptServer:
        class instance:
            routes = FakeRoutes()
            app = FakeApp()

    server_mod = types.ModuleType("server")
    server_mod.PromptServer = FakePromptServer

    web_mod = types.ModuleType("aiohttp.web")
    web_mod.middleware = lambda fn: fn
    web_mod.json_response = lambda data=None, status=200: {"data": data, "status": status}

    aiohttp_mod = types.ModuleType("aiohttp")
    aiohttp_mod.web = web_mod

    sys.modules["server"] = server_mod
    sys.modules["aiohttp"] = aiohttp_mod
    sys.modules["aiohttp.web"] = web_mod
    return FakePromptServer


def load_module():
    spec = importlib.util.spec_from_file_location("comfyui_kb_tools_under_test", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    fake_prompt_server = install_stubs()
    module = load_module()

    failures = []

    def check(name, condition):
        if condition:
            print("OK   {}".format(name))
        else:
            print("FAIL {}".format(name))
            failures.append(name)

    os.environ["MCP_TOKEN"] = "s3cr3t"
    check("token correcto -> True", module._token_ok("s3cr3t") is True)
    check("token incorrecto -> False", module._token_ok("incorrecto") is False)
    check("header None -> False", module._token_ok(None) is False)

    os.environ["MCP_TOKEN"] = ""
    check("MCP_TOKEN vacio -> False (header vacio)", module._token_ok("") is False)
    check("MCP_TOKEN vacio -> False (con header)", module._token_ok("s3cr3t") is False)

    os.environ.pop("MCP_TOKEN", None)
    check("MCP_TOKEN ausente -> False", module._token_ok("s3cr3t") is False)

    middlewares = fake_prompt_server.instance.app.middlewares
    check("rb_auth registrado en app.middlewares", module.rb_auth in middlewares)

    print("")
    if failures:
        print("{} fallo(s): {}".format(len(failures), ", ".join(failures)))
        return 1
    print("Todo OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

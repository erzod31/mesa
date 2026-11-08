"""Standalone update handoff. Tests import apply_request with a fake platform;
the real helper binary must never be executed by the shared-host QA workflow.
"""
import argparse
import ctypes
from server.windows_updates import apply_request


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--request',required=True)
    args=parser.parse_args()
    try:
        apply_request(args.request)
    except Exception as error:
        ctypes.windll.user32.MessageBoxW(None,str(error),'Mesa · actualización no completada',0x10)
        return 1
    return 0


if __name__=='__main__':
    raise SystemExit(main())

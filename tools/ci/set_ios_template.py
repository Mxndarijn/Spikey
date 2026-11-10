"""Points the iOS export preset's release template at a zip (CI only, not committed).

    python3 tools/ci/set_ios_template.py export_presets.cfg /path/to/flapjaw_ios.zip
"""

import re
import sys


def main() -> None:
    path, template = sys.argv[1], sys.argv[2]
    text = open(path, encoding="utf-8").read()
    # The iOS preset's options come after its name line; the first custom_template/release
    # after it is the iOS one.
    head, sep, rest = text.partition('platform="iOS"')
    if not sep:
        sys.exit("No iOS preset in " + path)
    rest, count = re.subn(
        r"(?m)^custom_template/release=.*$",
        'custom_template/release="%s"' % template,
        rest,
        count=1,
    )
    if count != 1:
        sys.exit("No custom_template/release in the iOS preset")
    open(path, "w", encoding="utf-8", newline="\n").write(head + sep + rest)
    print("iOS release template:", template)


if __name__ == "__main__":
    main()

"""Keep SDL's hidden input field from stealing focus from native UIKit forms.

SDL 3.4.2 observes all UITextField changes. Its password-manager workaround
temporarily activates SDL text input even for another controller's field,
which resigns the native field and hides its keyboard after the first key.
Apply a narrowly scoped, idempotent guard to the pinned dependency source.
"""
import argparse
from pathlib import Path

SIGNATURE = '- (void)textFieldTextDidChange:(NSNotification *)notification\n{\n'
GUARD = ('    // TH11: UIKit forms own their input; only process SDL field changes.\n'
         '    if (notification.object != textField) {\n'
         '        return;\n'
         '    }\n\n')


def patch_sdl(directory):
    source = directory / 'src/video/uikit/SDL_uikitviewcontroller.m'
    text = source.read_text(encoding='utf-8')
    if SIGNATURE + GUARD in text:
        print('SDL UIKit native text-field guard already applied')
        return
    if text.count(SIGNATURE) != 1:
        raise ValueError('Unsupported SDL UIKit source; review the pinned version before building')
    source.write_text(text.replace(SIGNATURE, SIGNATURE + GUARD, 1), encoding='utf-8')
    print('Applied SDL UIKit native text-field guard')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdl', type=Path)
    patch_sdl(parser.parse_args().sdl)

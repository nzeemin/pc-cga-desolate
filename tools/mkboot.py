"""Make a bootable 360K floppy image from a .COM file: mkboot.py in.com out.img"""
import subprocess, sys, os
com, out = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
data = open(com, 'rb').read()
sectors = (len(data) + 511) // 512
assert 0 < sectors <= 127, 'COM too big'
tmp = out + '.boot.bin'
subprocess.check_call([os.path.join(here, 'nasm.exe'), '-f', 'bin', f'-DSECTORS={sectors}',
                       os.path.join(here, 'boot.asm'), '-o', tmp])
boot = open(tmp, 'rb').read(); os.remove(tmp)
assert len(boot) == 512
img = boot + data
img += b'\0' * (368640 - len(img))
open(out, 'wb').write(img)

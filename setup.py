import sys
from setuptools import setup, Extension
from Cython.Build import cythonize

defines=[('HAVE_STDINT_H', '1'), ('HAVE_INTTYPES_H', '1')]
if sys.platform != 'win32':
    defines.append(('HAVE_BSWAP32', '1'))
module =Extension(name='flac_bitstream',
                  sources=['bitstream.pyx', 'src/bitmath.c', 'src/bitreader.c', 'src/bitwriter.c'],
                  include_dirs=['include'],
                  define_macros=defines,
                  language='c')
setup(name='flac_bitstream', ext_modules=cythonize(module))

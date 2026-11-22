"""Decode the regional maps in Blender, including single-channel OpenEXR roughness."""
import json
import sys
from pathlib import Path

import bpy
import numpy as np

assert bpy.app.background
for entry in json.loads(Path(sys.argv[sys.argv.index('--')+1]).read_text()):
    path, size, target = entry
    raster = bpy.data.images.load(path)
    raster.colorspace_settings.name = 'Non-Color'
    raster.scale(size,size)
    pixels = np.empty(size*size*4,dtype='f4')
    raster.pixels.foreach_get(pixels)
    rgb = pixels.reshape(size,size,4)[::-1,:,:3]
    if not np.isfinite(rgb).all() or rgb.max() <= .005:
        raise ValueError('Empty or invalid linear map '+path)
    np.save(target, np.uint8(np.clip(rgb,0,1)*255+.5))
    bpy.data.images.remove(raster)

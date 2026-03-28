#!/usr/bin/env python3
"""
prepare_dem.py — SRTM DEM Preprocessor for Pohang, South Korea
================================================================
Downloads SRTM 1-arc-second tile N36E129.hgt and crops a 512x512 region
centered on Pohang city (36.019°N, 129.343°E).

Output: pohang_dem.raw (16-bit signed little-endian, 512x512 = 524,288 bytes)

Usage:
    python3 prepare_dem.py
    python3 prepare_dem.py --hgt /path/to/N36E129.hgt   # Use existing file

Requires: numpy
"""

import argparse
import json
import os
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

# ── Constants ──────────────────────────────────────────────────────────────

TILE_NAME = "N36E129"
TILE_SIZE = 3601               # 1-arc-second SRTM tile dimension
CROP_SIZE = 512                # Output grid size

# Pohang city center
POHANG_LAT = 36.019
POHANG_LON = 129.343

# SRTM tile SW corner
TILE_LAT_SW = 36
TILE_LON_SW = 129

# Download URLs (try in order)
SRTM_URLS = [
    f"https://srtm.csi.cgiar.org/wp-content/uploads/files/srtm_5x5/TIFF/srtm_68_07.zip",
    f"https://elevation-tiles-prod.s3.amazonaws.com/skadi/N36/{TILE_NAME}.hgt.gz",
]

OUTPUT_DIR = Path(__file__).parent
OUTPUT_FILE = OUTPUT_DIR / "pohang_dem.raw"
METADATA_FILE = OUTPUT_DIR / "pohang_dem_meta.json"


def lat_lon_to_pixel(lat: float, lon: float) -> tuple:
    """Convert lat/lon to SRTM pixel coordinates (row, col)."""
    # Row 0 = north edge of tile (tile_lat + 1), row 3600 = south edge
    row = int((TILE_LAT_SW + 1 - lat) * (TILE_SIZE - 1))
    col = int((lon - TILE_LON_SW) * (TILE_SIZE - 1))
    return row, col


def read_hgt(path: str) -> np.ndarray:
    """Read an SRTM .hgt file as a numpy array."""
    data = np.fromfile(path, dtype=">i2")  # big-endian int16
    if data.size != TILE_SIZE * TILE_SIZE:
        raise ValueError(f"Expected {TILE_SIZE*TILE_SIZE} pixels, got {data.size}")
    return data.reshape((TILE_SIZE, TILE_SIZE))


def download_hgt(output_path: str) -> str:
    """Try to download SRTM tile. Returns path to .hgt file."""
    # Try S3 gzip source first
    gz_url = f"https://elevation-tiles-prod.s3.amazonaws.com/skadi/N36/{TILE_NAME}.hgt.gz"
    print(f"Downloading from: {gz_url}")
    try:
        import gzip
        gz_path = output_path + ".gz"
        urllib.request.urlretrieve(gz_url, gz_path)
        with gzip.open(gz_path, 'rb') as f_in:
            with open(output_path, 'wb') as f_out:
                f_out.write(f_in.read())
        os.remove(gz_path)
        print(f"Downloaded and decompressed: {output_path}")
        return output_path
    except Exception as e:
        print(f"S3 download failed: {e}")

    print("Could not download SRTM data automatically.")
    print("Please download N36E129.hgt manually from:")
    print("  - https://dwtkns.com/srtm30m/")
    print("  - https://portal.opentopography.org/")
    print("Then run: python3 prepare_dem.py --hgt /path/to/N36E129.hgt")
    sys.exit(1)


def crop_and_export(tile: np.ndarray, center_lat: float, center_lon: float):
    """Crop tile around center point and export as raw LE int16."""
    crow, ccol = lat_lon_to_pixel(center_lat, center_lon)
    half = CROP_SIZE // 2

    # Ensure crop stays within tile bounds
    r0 = max(0, crow - half)
    c0 = max(0, ccol - half)
    r1 = min(TILE_SIZE, r0 + CROP_SIZE)
    c1 = min(TILE_SIZE, c0 + CROP_SIZE)
    r0 = r1 - CROP_SIZE
    c0 = c1 - CROP_SIZE

    crop = tile[r0:r1, c0:c1].copy()

    # Handle SRTM voids (-32768)
    void_mask = crop <= -32768
    if void_mask.any():
        crop[void_mask] = 0
        print(f"Filled {void_mask.sum()} void pixels with 0")

    # Convert to little-endian int16
    crop_le = crop.astype("<i2")

    # Write raw binary
    crop_le.tofile(str(OUTPUT_FILE))
    print(f"Wrote {OUTPUT_FILE} ({crop_le.nbytes:,} bytes)")

    # Compute metadata
    # Latitude/longitude bounds of the crop
    lat_north = TILE_LAT_SW + 1 - r0 / (TILE_SIZE - 1)
    lat_south = TILE_LAT_SW + 1 - r1 / (TILE_SIZE - 1)
    lon_west = TILE_LON_SW + c0 / (TILE_SIZE - 1)
    lon_east = TILE_LON_SW + c1 / (TILE_SIZE - 1)

    # Pixel spacing in meters at Pohang latitude
    lat_rad = np.radians(center_lat)
    m_per_arcsec_ns = 30.87  # ~1 arcsec at any latitude
    m_per_arcsec_ew = 30.87 * np.cos(lat_rad)  # ~24.89 at 36°N

    elev_min = int(crop.min())
    elev_max = int(crop.max())

    meta = {
        "file": "pohang_dem.raw",
        "width": CROP_SIZE,
        "height": CROP_SIZE,
        "dtype": "int16_le",
        "bounds": {
            "lat_north": round(lat_north, 6),
            "lat_south": round(lat_south, 6),
            "lon_west": round(lon_west, 6),
            "lon_east": round(lon_east, 6),
        },
        "spacing_meters": {
            "x": round(m_per_arcsec_ew, 2),
            "y": round(m_per_arcsec_ns, 2),
        },
        "elevation_range": {
            "min_m": elev_min,
            "max_m": elev_max,
        },
        "center": {
            "lat": center_lat,
            "lon": center_lon,
        },
        "source": f"SRTM 1-arc-second, tile {TILE_NAME}",
    }

    with open(METADATA_FILE, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"Wrote metadata: {METADATA_FILE}")
    print(f"Elevation range: {elev_min}m – {elev_max}m")
    print(f"Spacing: {m_per_arcsec_ew:.2f}m (E-W) × {m_per_arcsec_ns:.2f}m (N-S)")
    print(f"Bounds: {lat_south:.4f}°N–{lat_north:.4f}°N, {lon_west:.4f}°E–{lon_east:.4f}°E")


def main():
    parser = argparse.ArgumentParser(description="Prepare Pohang DEM data")
    parser.add_argument("--hgt", help="Path to existing N36E129.hgt file")
    parser.add_argument("--lat", type=float, default=POHANG_LAT, help="Center latitude")
    parser.add_argument("--lon", type=float, default=POHANG_LON, help="Center longitude")
    args = parser.parse_args()

    # Get HGT tile
    if args.hgt:
        hgt_path = args.hgt
    else:
        hgt_path = str(OUTPUT_DIR / f"{TILE_NAME}.hgt")
        if not os.path.exists(hgt_path):
            download_hgt(hgt_path)

    print(f"Reading {hgt_path}...")
    tile = read_hgt(hgt_path)
    print(f"Tile loaded: {tile.shape}, range {tile.min()}–{tile.max()}m")

    crop_and_export(tile, args.lat, args.lon)
    print("\nDone! pohang_dem.raw is ready for VTKSwift.")


if __name__ == "__main__":
    main()

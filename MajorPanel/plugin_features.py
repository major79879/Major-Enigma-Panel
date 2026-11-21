import re
import struct
from urllib.parse import urlsplit
import zlib


_NORMALIZE_RE = re.compile(r"[^a-z0-9]")
_VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_PLUGIN_IMAGE_BYTES = 3 * 1024 * 1024
MAX_PLUGIN_IMAGE_WIDTH = 1920
MAX_PLUGIN_IMAGE_HEIGHT = 1080


def _normalize(value):
    return _NORMALIZE_RE.sub("", value.lower())


def plugin_key(category, name):
    return "%s|%s" % (_normalize(category or ""), _normalize(name or ""))


def plugin_names_by_key(categories):
    names = {}
    for _category, items in categories:
        for item in items:
            name = item.get("name", "")
            key = plugin_key(item.get("cat", ""), name)
            if key != "|":
                names[key] = name
    return names


def normalize_plugin_image_map(data):
    if not isinstance(data, dict):
        raise ValueError("plugin image config must be a JSON object")

    result = {}
    for key, url in data.items():
        if not isinstance(key, str) or "|" not in key:
            raise ValueError("image keys must use Category|Plugin Name")
        category, name = key.split("|", 1)
        normalized_key = plugin_key(category, name)
        if not category.strip() or not name.strip() or normalized_key == "|":
            raise ValueError("image keys must include a category and plugin name")
        if normalized_key in result:
            raise ValueError("duplicate plugin image key: %s" % key)
        if not isinstance(url, str):
            raise ValueError("image URLs must be strings")
        parts = urlsplit(url)
        if parts.scheme != "https" or parts.hostname != "raw.githubusercontent.com" or not parts.path.strip("/"):
            raise ValueError("image URLs must be raw.githubusercontent.com HTTPS links")
        result[normalized_key] = url
    return result


def added_plugin_keys(previous, current):
    return sorted(set(current) - set(previous))


def is_newer_version(remote, current):
    if not isinstance(remote, str) or not isinstance(current, str):
        return False
    if not _VERSION_RE.match(remote) or not _VERSION_RE.match(current):
        return False
    remote_parts = [int(part) for part in remote.split(".")]
    current_parts = [int(part) for part in current.split(".")]
    width = max(len(remote_parts), len(current_parts))
    remote_parts.extend([0] * (width - len(remote_parts)))
    current_parts.extend([0] * (width - len(current_parts)))
    return tuple(remote_parts) > tuple(current_parts)


def validate_plugin_png(data):
    if not isinstance(data, bytes) or len(data) < 45 or len(data) > MAX_PLUGIN_IMAGE_BYTES:
        raise ValueError("plugin image must be a PNG no larger than 3 MiB")
    if data[:8] != _PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("plugin image is not a valid PNG")
    width, height = struct.unpack(">II", data[16:24])
    if not width or not height or width > MAX_PLUGIN_IMAGE_WIDTH or height > MAX_PLUGIN_IMAGE_HEIGHT:
        raise ValueError("plugin image dimensions exceed 1920x1080")
    offset = 8
    saw_header = False
    saw_end = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("truncated PNG chunk")
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length:end])[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != expected_crc:
            raise ValueError("invalid PNG checksum")
        if not saw_header:
            if kind != b"IHDR" or length != 13:
                raise ValueError("invalid PNG header")
            saw_header = True
        if kind == b"IEND":
            if length or end != len(data):
                raise ValueError("invalid PNG end chunk")
            saw_end = True
            break
        offset = end
    if not saw_header or not saw_end:
        raise ValueError("incomplete PNG image")
    return data


def frame_png(width, height, colors, thickness=5):
    """Return a transparent PNG with a solid or horizontal-gradient rectangular border."""
    if not isinstance(width, int) or not isinstance(height, int) or width < 8 or height < 8:
        raise ValueError("square frame size must be an integer of at least 8")
    if not isinstance(thickness, int) or thickness < 1 or thickness >= min(width, height) // 2:
        raise ValueError("square frame thickness is out of range")

    if (isinstance(colors, (tuple, list)) and len(colors) == 3
            and all(isinstance(channel, int) for channel in colors)):
        palette = [tuple(colors)]
    else:
        try:
            palette = [tuple(color) for color in colors]
        except (TypeError, ValueError):
            raise ValueError("square frame colors must be RGB colors")
        if not palette or any(len(color) != 3 or
                              any(not isinstance(channel, int) or not 0 <= channel <= 255
                                  for channel in color)
                              for color in palette):
            raise ValueError("square frame colors must contain RGB channels")

    def color_at(position):
        if len(palette) == 1:
            return palette[0]
        scaled = min(1.0, max(0.0, position)) * (len(palette) - 1)
        index = int(scaled)
        if index == len(palette) - 1:
            return palette[index]
        fraction = scaled - index
        start, end = palette[index], palette[index + 1]
        return tuple(int(a + (b - a) * fraction + 0.5) for a, b in zip(start, end))

    rows = []
    for y in range(height):
        row = bytearray(b"\x00")
        for x in range(width):
            inside_border = x < thickness or y < thickness or x >= width - thickness or y >= height - thickness
            row.extend(color_at(x / float(width - 1)))
            row.append(255 if inside_border else 0)
        rows.append(row)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    image = (b"\x89PNG\r\n\x1a\n"
             + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
             + chunk(b"IEND", b""))
    return image


def square_frame_png(size, colors, thickness=5):
    """Return a transparent PNG with a solid or horizontal-gradient square border."""
    if not isinstance(size, int) or size < 8:
        raise ValueError("square frame size must be an integer of at least 8")
    return frame_png(size, size, colors, thickness)

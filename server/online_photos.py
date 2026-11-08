"""Photo metadata only: recipe imports and persistence never fetch image bytes."""
from urllib.parse import urlsplit
import ipaddress


def online_photo_url(value):
    if not isinstance(value, str) or len(value) > 10000:
        return False
    try:
        url = urlsplit(value)
        host = url.hostname or ''
        if (url.scheme != 'https' or url.username or url.password or
                url.port not in (None, 443) or url.fragment or '.' not in host or
                any(host == s or host.endswith('.'+s) for s in
                    ('localhost', 'local', 'internal', 'ts.net'))):
            return False
        try:
            return ipaddress.ip_address(host).is_global
        except ValueError:
            return True  # The displaying device validates DNS and pins the IP.
    except ValueError:
        return False


def online_recipe_data(data):
    result = dict(data)
    legacy = result.pop('image', '')
    cover = result.get('image_url', '')
    photos = []
    if isinstance(data.get('photos'), list):
        for item in data['photos']:
            if not isinstance(item, dict) or not online_photo_url(item.get('url')):
                continue
            photo = dict(item)
            encoded = photo.pop('image', '')
            photo.pop('error', None)
            if legacy and encoded == legacy:
                cover = photo['url']
            photos.append(photo)
        result['photos'] = photos
    if online_photo_url(cover):
        result['image_url'] = cover
        if not any(p['url'] == cover for p in photos):
            result['photos'] = [{'url': cover, 'caption': 'Foto de la receta'}, *photos]
    else:
        result.pop('image_url', None)
    return result


def online_photo_tree(value):
    if isinstance(value, list):
        return [online_photo_tree(item) for item in value]
    if not isinstance(value, dict):
        return value
    result = {k: online_photo_tree(v) for k, v in value.items() if k != 'image_data'}
    if ('photos' in result or 'image_url' in result or
            ('ingredients' in result and 'image' in result)):
        return online_recipe_data(result)
    return result

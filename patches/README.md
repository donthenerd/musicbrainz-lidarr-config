# LMD Patches

This directory contains patches for the Lidarr Metadata Server (LMD).

## provider.py - Fanart.tv URL Fix

**Issue:** LMD's `FanartTvProvider.build_url()` method adds a trailing slash before the query string, causing fanart.tv API to return 404 errors.

**Original (broken):**
```python
url += '/?api_key={api_key}'.format(api_key=self._api_key)
```

**Fixed:**
```python
url += '?api_key={api_key}'.format(api_key=self._api_key)
```

**Location:** Line 812 in `lidarrmetadata/provider.py`

### How to Apply

1. Copy the patched file from the LMD container:
   ```bash
   docker cp musicbrainz-docker-lmd-1:/metadata/lidarrmetadata/provider.py ./patches/
   ```

2. Edit line 812 to remove the trailing slash before `?api_key`

3. Mount as read-only volume in docker-compose (see lmd-settings.yml)

### Verification

Test that fanart.tv returns 200 (not 404):
```bash
curl -I "https://webservice.fanart.tv/v3/music/79239441-bfd5-4981-a70c-55c3f15c1287?api_key=YOUR_KEY"
```

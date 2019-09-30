local config_path = assert(os.getenv('TINYSTASH_CONFIG_PATH'), 'TINYSTASH_CONFIG_PATH is not set')
local chunk = assert(loadfile(config_path))
local _, config = assert(pcall(chunk))

local _processed = {}
-- config._processed contains some calculated/normalized values (for the sake of convenience and brevity)
config._processed = _processed

local config_tg = config.tg

-- config.link_url_prefix without trailing slash(es)
_processed.link_url_prefix = config.link_url_prefix:match('(.-)/*$')
-- enable upload (both via html form and via direct upload api)
_processed.enable_upload = config_tg.upload_chat_id ~= nil
-- config.enable_upload_api corrected accordind to config._processed.enable_upload
_processed.enable_upload_api = _processed.enable_upload and config.enable_upload_api
-- tg webhook secret, either set explicitly (arbitrary string) or implicitly (bot api token)
_processed.tg_webhook_secret = config_tg.webhook_secret or config_tg.token

return config

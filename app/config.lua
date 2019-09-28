local config_path = assert(os.getenv('TINYSTASH_CONFIG_PATH'), 'TINYSTASH_CONFIG_PATH is not set')
local chunk = assert(loadfile(config_path))
local _, config = assert(pcall(chunk))
return config

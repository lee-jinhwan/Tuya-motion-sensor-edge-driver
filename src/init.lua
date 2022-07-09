local ZigbeeDriver = require "st.zigbee"

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local constants = require "st.zigbee.constants"
local defaults = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"

local utils = require "st.utils"
local log = require "log"
local json = require "dkjson"

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local battery = capabilities.battery

local function sensor_clear_time_handler(driver, device, value, zb_rx)
    log.debug("sensor_clear_time_handler : " .. value.value)
end

local battery_remaining_handler = function(driver, device, value, zb_rx)
    log.debug("battery_remaining_handler")
    device:emit_event(battery.battery(value.value // 2))
end

local init = function(driver, device) 
    log.debug("initialize device")
    battery_defaults.build_linear_voltage_init(2.3, 3.0)
end

local function refersh_handler(driver, device)
    log.debug("refresh")
    device:refresh()
end

local device_added = function(driver, device)
    log.debug("device added")
    
    device:refresh()

    cluster_id = data_types.ClusterId(zcl_clusters.IASZone.ID)
    attribute_id = data_types.AttributeId(zcl_clusters.IASZone.attributes.ZoneState.ID)
    device:send(cluster_base.read_attribute(device, cluster_id, attribute_id))

    cluster_id = data_types.ClusterId(zcl_clusters.PowerConfiguration.ID)
    attribute_id = data_types.AttributeId(zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.ID)
    device:send(cluster_base.read_attribute(device, cluster_id, attribute_id))

    cluster_id = data_types.ClusterId(zcl_clusters.IASZone.ID)
    attribute_id = data_types.AttributeId(0xF001)
    payload = data_types.Uint8(0)
    device:send(cluster_base.write_attribute(device, cluster_id, attribute_id, payload))
    device:send(cluster_base.read_attribute(device, cluster_id, attribute_id))
end

local do_configure = function(driver, device)
    log.debug("do configure")
    
    device_management.configure(driver, device)

    device:send(device_management.build_bind_request(device, zcl_clusters.PollControl.ID, driver.environment_info.hub_zigbee_eui))
    device:send(zcl_clusters.PollControl.attributes.CheckInInterval:configure_reporting(device, 0, 3600, 0))
    device:send(zcl_clusters.PollControl.attributes.CheckInInterval:write(device, data_types.Uint32(30)))
end

local function info_changed(driver, device, event, args)
    log.debug("info changed: " .. tostring(event) .. ", " .. tostring(args))
    log.debug("device preference: " .. json.encode(device.preferences))

    for id, value in pairs(device.preferences) do
        if args.old_st_store.preferences[id] ~= value then
            local value = device.preferences[id]
            log.info("preferences changed: " .. id .. " " .. tostring(value))

            if id == "motionClearTime" then
                cluster_id = data_types.ClusterId(zcl_clusters.IASZone.ID)
                attribute_id = data_types.AttributeId(0xF001)
                payload = data_types.Uint8(tonumber(value))
                device:send(cluster_base.write_attribute(device, cluster_id, attribute_id, payload))
            end
        end
    end
end

----------------------Driver configuration----------------------

local zigbee_motion_driver = {
    supported_capabilities = {
        capabilities.motionSensor,
        capabilities.battery,
        capabilities.refresh
    },
    capability_handlers = {
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = refersh_handler
        }
    },
    zigbee_handlers = {
        attr = {
            [zcl_clusters.IASZone.ID] = {
                [0xF001] = sensor_clear_time_handler
            },
            [zcl_clusters.PowerConfiguration.ID] = {
                [zcl_clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_remaining_handler
            }
        },
        zdo = {}
    },
    lifecycle_handlers = {
        init = init,
        added = device_added,
        doConfigure = do_configure,
        infoChanged = info_changed
    },
    ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
}

--Run driver
defaults.register_for_default_handlers(zigbee_motion_driver, zigbee_motion_driver.supported_capabilities)

local driver = ZigbeeDriver("motion-sensor", zigbee_motion_driver)
driver:run()

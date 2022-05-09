local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local ZigbeeDriver = require "st.zigbee"
local constants = require "st.zigbee.constants"
local defaults = require "st.zigbee.defaults"
local battery = capabilities.battery
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"
local log = require "log"
local json = require "dkjson"

local generate_event_from_zone_status = function(driver, device, zone_status, zigbee_message)
    device:emit_event_for_endpoint(
        zigbee_message.address_header.src_endpoint.value,
        (zone_status:is_alarm1_set() or zone_status:is_alarm2_set()) and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive()
    )
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
    generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
    generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local battery_handler = function(driver, device, value, zb_rx)
    log.debug("battery voltage : " .. value.value)
    local batteryMap = {
        [28] = 100,
        [27] = 100,
        [26] = 100,
        [25] = 90,
        [24] = 90,
        [23] = 70,
        [22] = 70,
        [21] = 50,
        [20] = 50,
        [19] = 30,
        [18] = 30,
        [17] = 15,
        [16] = 1,
        [15] = 0
    }
    local minVolts = 15
    local maxVolts = 28
    value = utils.clamp_value(value.value, minVolts, maxVolts)

    device:emit_event(battery.battery(batteryMap[value]))
end

local init = function(driver, device) 
    log.debug("initialize device")
    battery_defaults.build_linear_voltage_init(2.3, 3.0)
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
end

local do_configure = function(driver, device)
    log.debug("do configure")
    
    device_management.configure(driver, device)
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
        capabilities.battery
    },
    zigbee_handlers = {
        global = {},
        cluster = {
            [zcl_clusters.IASZone.ID] = {
                [zcl_clusters.IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler,
            }
        },
        attr = {
            [zcl_clusters.IASZone.ID] = {
                [zcl_clusters.IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
            },
            [zcl_clusters.PowerConfiguration.ID] = {
                [zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.ID] = battery_handler
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
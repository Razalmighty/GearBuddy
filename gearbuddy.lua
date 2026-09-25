addon.name = "GearBuddy";
addon.author = "GearBuddy contributors";
addon.version = "0.1.0-alpha.8";
addon.desc = "Read-only, event-driven equipment planning for HorizonXI.";

require("common");

local App = require("core.app");
local instance = App.new();

ashita.events.register("load", "gearbuddy_load", function()
    instance:onLoad();
end);

ashita.events.register("unload", "gearbuddy_unload", function()
    instance:onUnload();
end);

ashita.events.register("packet_in", "gearbuddy_packet_in", function(event)
    instance:onPacketIn(event);
end);

ashita.events.register("command", "gearbuddy_command", function(event)
    instance:onCommand(event);
end);

ashita.events.register("d3d_present", "gearbuddy_present", function()
    instance:present();
end);

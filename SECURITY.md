# Security and privacy

GearBuddy has no network client, credential handling, telemetry, or remote update
path. The approval alpha reads local game memory through Ashita's public runtime
interfaces and displays local results. It does not persist character state or an
inventory snapshot. The settings document may store an item ID only when the
player explicitly pins that item to a profile slot; it never stores the inventory
list, count, bag, index, or resolved equipment plan.

The compatibility self-test and approval report remain local. They print only
aggregate counts, state labels, and failure reasons; they do not print character
names, item names, or a complete inventory. Running either command does not
enumerate bags or send network traffic.

Report unexpected packet mutation, action interception, external communication,
or persistent-data behavior as a release blocker.

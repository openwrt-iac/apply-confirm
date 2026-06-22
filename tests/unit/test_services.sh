# The deterministic static service map (src/lib/snapshot.sh ac_services_for).
# ac_init_exists is stubbed in run_unit.sh with a fixed installed set, so the
# same-name fallback is host-independent here.

it "system reloads its own init plus log and sysntpd"
assert_eq "system log sysntpd" "$(ac_services_for "system")"

it "dhcp reloads dnsmasq and odhcpd"
assert_eq "dnsmasq odhcpd" "$(ac_services_for "dhcp")"

it "wireless reloads network"
assert_eq "network" "$(ac_services_for "wireless")"

it "a same-name package with an init script maps to itself"
assert_eq "firewall" "$(ac_services_for "firewall")"

it "a package with no init script contributes nothing"
assert_eq "" "$(ac_services_for "nosuchpkg")"

it "overlapping services across packages are de-duplicated"
# network (-> network) + wireless (-> network) collapse to one entry.
assert_eq "network" "$(ac_services_for "network wireless")"

it "multiple packages union their service sets in order"
assert_eq "firewall dnsmasq odhcpd" "$(ac_services_for "firewall dhcp")"

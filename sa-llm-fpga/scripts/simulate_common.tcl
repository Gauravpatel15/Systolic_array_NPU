if {[llength [get_projects -quiet]] == 0} { error "First source scripts/create_project.tcl" }
catch {close_sim}
set sa_root [file normalize [file join [file dirname [info script]] ..]]
# OneDrive can mark generated directories read-only after the first run.
# Vivado checks this Windows attribute even when the directory ACL allows writes.
# Change directory attributes only inside this project's generated build tree.
proc sa_make_build_dirs_writable {directory} {
    file attributes $directory -readonly 0
    foreach child [glob -nocomplain -directory $directory -types d *] {
        sa_make_build_dirs_writable $child
    }
}
if {$::tcl_platform(platform) eq "windows"} {
    sa_make_build_dirs_writable [file join $sa_root build vivado]
}
set_property top $sa_sim_top [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
log_wave -r /*
if {$sa_sim_top eq "tb_mac_pe"} {
    add_wave /tb_mac_pe/clk /tb_mac_pe/a /tb_mac_pe/b /tb_mac_pe/av /tb_mac_pe/bv
    add_wave /tb_mac_pe/ce /tb_mac_pe/clear /tb_mac_pe/acc
} else {
    add_wave /tb_systolic_array/test2/clk /tb_systolic_array/test2/clear
    add_wave /tb_systolic_array/test2/ce /tb_systolic_array/test2/a_left
    add_wave /tb_systolic_array/test2/b_top /tb_systolic_array/test2/results
}
set_property needs_save false [current_wave_config]
run all
puts "Read the simulation log: success requires PASS $sa_sim_top and no Fatal/Error."

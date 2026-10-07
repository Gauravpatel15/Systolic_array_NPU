set sa_script_dir [file dirname [file normalize [info script]]]
set sa_sim_top tb_systolic_array
source [file join $sa_script_dir simulate_common.tcl]

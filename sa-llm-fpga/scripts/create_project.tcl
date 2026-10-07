# Run with `source {.../scripts/create_project.tcl}` from the Vivado Tcl Console.
set sa_root [file normalize [file join [file dirname [info script]] ..]]
set sa_project_dir [file join $sa_root build vivado]
set sa_project_file [file join $sa_project_dir sa_llm.xpr]
if {[llength [get_projects -quiet]] > 0} {
    error "A project is open. Save it and use close_project before creating/opening SA-LLM."
}
if {[file exists $sa_project_file]} {
    open_project $sa_project_file
} else {
    # Device target only; simulation needs neither a board nor Digilent board files.
    create_project sa_llm $sa_project_dir -part xc7z020clg400-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
    add_files -norecurse [glob [file join $sa_root rtl *.sv]]
    add_files -fileset sim_1 -norecurse [glob [file join $sa_root sim tb_*.sv]]
    add_files -fileset sim_1 -norecurse [glob [file join $sa_root sim vectors *.mem]]
    set_property top systolic_array [get_filesets sources_1]
    set_property top tb_mac_pe [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
}
puts "SA-LLM project ready: $sa_project_file"
puts "Next: [list source [file join $sa_root scripts simulate_pe.tcl]]"

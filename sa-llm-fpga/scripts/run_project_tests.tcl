# Optional batch check of the same scripts used from the GUI Tcl Console.
set sa_scripts [file dirname [file normalize [info script]]]
source [file join $sa_scripts create_project.tcl]
foreach sa_test {pe array} {
    source [file join $sa_scripts simulate_${sa_test}.tcl]
    # Closing flushes the simulator log before the PASS check reads it.
    close_sim -force
    set sa_log [file join [get_property DIRECTORY [current_project]] sa_llm.sim sim_1 behav xsim simulate.log]
    if {![file exists $sa_log]} { error "Expected XSim log missing: $sa_log" }
    set sa_fd [open $sa_log r]
    set sa_text [read $sa_fd]
    close $sa_fd
    if {![string match "*PASS ${sa_sim_top}:*" $sa_text] || [regexp -line {^\s*(Fatal:|ERROR:)} $sa_text]} {
        error "Simulation failed or PASS missing: $sa_sim_top; read $sa_log"
    }
}
puts "PASS project Tcl workflow"
close_project

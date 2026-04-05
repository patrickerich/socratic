# Vivado project-mode build script for the Socratic AXKU5 Ibex target.
#
# Usage:
#   make fpga-flist
#   vivado -mode batch -source rtl/platform/fpga/boards/axku5/build_axku5.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ../../../..]]
set build_dir  [file normalize [file join $repo_dir build/fpga]]
set flist_file [file join $build_dir socratic_ibex_axku5_wrap.f]
set inc_file   [file join $build_dir socratic_ibex_axku5_wrap_incdirs.txt]
set xdc_file   [file join $script_dir axku5.xdc]
set part_name  "xcku5p-ffvb676-2-e"
set proj_name  "socratic_ibex_axku5"
set proj_dir   [file join $build_dir $proj_name]
set top_name   "socratic_ibex_axku5_wrap"

if {![file exists $flist_file]} {
  puts "ERROR: Missing file list $flist_file"
  puts "ERROR: Run 'make fpga-flist' first."
  return -code error
}

if {![file exists $xdc_file]} {
  puts "ERROR: Missing constraints file $xdc_file"
  return -code error
}

file mkdir $proj_dir
create_project -force $proj_name $proj_dir -part $part_name

set src_fs [get_filesets sources_1]
set constr_fs [get_filesets constrs_1]

set sv_files {}
set fh [open $flist_file r]
while {[gets $fh line] >= 0} {
  set line [string trim $line]
  if {$line eq ""} { continue }
  if {[string match "#*" $line]} { continue }
  if {[file extension $line] ni {".sv" ".v"}} { continue }
  if {[file pathtype $line] eq "absolute"} {
    set full $line
  } else {
    set full [file normalize [file join $repo_dir $line]]
  }
  add_files -fileset $src_fs -norecurse $full
  lappend sv_files $full
}
close $fh

if {[llength $sv_files] > 0} {
  set_property file_type {SystemVerilog} [get_files -of_objects $src_fs]
}

if {[file exists $inc_file]} {
  set incdir_line [string trim [read [open $inc_file r]]]
  if {$incdir_line ne ""} {
    set tokens  [split $incdir_line " "]
    set incdirs {}
    set expect_path 0
    foreach tok $tokens {
      if {$tok eq "-incdir"} {
        set expect_path 1
      } elseif {$expect_path} {
        if {[file pathtype $tok] eq "absolute"} {
          lappend incdirs $tok
        } else {
          lappend incdirs [file normalize [file join $repo_dir $tok]]
        }
        set expect_path 0
      }
    }
    if {[llength $incdirs] > 0} {
      set_property include_dirs $incdirs $src_fs
    }
  }
}

add_files -fileset $constr_fs $xdc_file
set_property top $top_name $src_fs
update_compile_order -fileset $src_fs

launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

open_run impl_1
set bit_file [file join $proj_dir "${top_name}.bit"]
write_bitstream -force $bit_file
puts "INFO: Bitstream written to $bit_file"

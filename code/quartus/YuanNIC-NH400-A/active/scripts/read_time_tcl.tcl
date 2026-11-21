set target_file "../rtl_src/sys_cfg/compile_time.v"  
set target_file_abs [file normalize $target_file]
puts "Target file: $target_file_abs"

set current_time [clock seconds]
set year_month_day [clock format $current_time -format "%Y%m%d"]
set hour_min_sec [clock format $current_time -format "%H%M%S"]
set compile_time1 "`define COMPILE_TIME1  32'h$year_month_day"
set compile_time2 "`define COMPILE_TIME2  32'h$hour_min_sec"
puts "Update time for this run: COMPILE_TIME1=$year_month_day, COMPILE_TIME2=$hour_min_sec"

if {![file exists $target_file_abs]} {
    set parent_dir [file dirname $target_file_abs]
    file mkdir $parent_dir
    set f [open $target_file_abs wb]
    puts -nonewline $f "// Compilation time macro definition file (auto-updated)\n"
    puts -nonewline $f "$compile_time1\n$compile_time2\n"
    close $f
    puts "File created for the first time, initial time macros have been written"
    exit 0
}

set f [open $target_file_abs rb]
set raw_content [read $f]
close $f

set utf8_bom "\xef\xbb\xbf"
set clean_content [string map [list $utf8_bom ""] $raw_content]
set file_lines [split $clean_content "\n"]
set file_lines [lmap line $file_lines {string trimright $line "\r"}]

set new_lines [list]
set updated1 0
set updated2 0

foreach line $file_lines {
    if {[string match "*COMPILE_TIME1*" $line]} {
        lappend new_lines $compile_time1
        set updated1 1
    } elseif {[string match "*COMPILE_TIME2*" $line]} {
        lappend new_lines $compile_time2
        set updated2 1
    } else {
        lappend new_lines $line
    }
}

if {$updated1 == 0} {
    lappend new_lines $compile_time1
    set updated1 1
}
if {$updated2 == 0} {
    lappend new_lines $compile_time2
    set updated2 1
}

set final_content [join $new_lines "\r\n"]
set f [open $target_file_abs wb]
puts -nonewline $f $final_content
close $f

if {$updated1 && $updated2} {
    puts " Time macros forced update completed!"
} else {
    puts " Partial macros not updated: COMPILE_TIME1=[expr {$updated1?"success":"failed"}], COMPILE_TIME2=[expr {$updated2?"success":"failed"}]"
}
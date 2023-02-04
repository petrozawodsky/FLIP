#dbgBeginSrc [info script]
global atmelProtocol protocol retryPossible
global select_node prog_start prog_data display_data write_command read_command ciError dongle
set atmelProtocol(ci_select_node) 0
set atmelProtocol(ci_prog_start) 1
set atmelProtocol(ci_prog_data) 2
set atmelProtocol(ci_display_data) 3
set atmelProtocol(ci_write_command) 4
set atmelProtocol(ci_read_command) 5
set atmelProtocol(ci_error) 6
set atmelProtocol(dongle) FFFF
set select_node [format %04X [expr $atmelProtocol(ci_select_node) - 0x$::deviceArray(crisConnect)0]]
set prog_start [format %04X [expr $atmelProtocol(ci_prog_start) - 0x$::deviceArray(crisConnect)0]]
set prog_data [format %04X [expr $atmelProtocol(ci_prog_data) - 0x$::deviceArray(crisConnect)0]]
set display_data [format %04X [expr $atmelProtocol(ci_display_data) - 0x$::deviceArray(crisConnect)0]]
set write_command [format %04X [expr $atmelProtocol(ci_write_command) - 0x$::deviceArray(crisConnect)0]]
set read_command [format %04X [expr $atmelProtocol(ci_read_command) - 0x$::deviceArray(crisConnect)0]]
set ciError [format %04X [expr $atmelProtocol(ci_error) - 0x$::deviceArray(crisConnect)0]]
set dongle [format %04X 0x$atmelProtocol(dongle)]
set retryPossible 1
if {! [info exists protocol(frameLengthW)]} then {
    set protocol(frameLengthW) 128
    set protocol(frameLengthR) 128
}
proc ptclInitComm {} {
    global canBaud flipStates
    #dbgBeginProc [info level [info level]]
    set status [ptclInitRs232Comm]
    if {$status == 1} then {
	set CRIS [format %08X 0x$::deviceArray(crisConnect)]
	set bitrate [format %04X [string range $canBaud 0 end-1]]
	set protocol "00"
	set status [ptclInitDongle $bitrate $protocol $CRIS]
    }
    if {$status != 1} then {
	ptclCancelRs232Comm
	set status 0
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclInitRs232Comm {} {
    #dbgBeginProc [info level [info level]]
    global flipStates port baud baudList prot waitTime extraTimeOut loadConfig projDir
    log_message "Selected protocol : $prot Rs232"
    log_message "Initializing Rs232 communication..."
    set sync 0
    #dbgShowVar "port = $port"
    #dbgShowVar "baud = $baud"
    if {![info exists ::sio::devId]} then {
	set ::sio::devId [::sio::openDevice $port $baud async n 8 1 0]
    }
    if {$::sio::devId != 0} then {
	set loadConfig(globals) "global port baud"
	set loadConfig(port) "set port $port"
	set loadConfig(baud) "set baud $baud"
	set loadConfig(initComm) "connectRS232 Standard"
	::sio::setBaud $baud
	set sync [::sio::autoBaudSync "U" $waitTime(standard)]
	if {$sync == 1} then {
	    updateGUI onRs232CommunicationOn
	    log_message "Rs232 communication initialized."
	    log_message "Dongle Initialization"
	} elseif {$sync == -1} {
	    updateGUI onRs232CommunicationOff
	    set message "The board reply is not correct."
	    messageBox "RS232 Communication" error $message
	    log_message "RS232 Communication Error."
	} else {
	    set message "Time out error."
	    messageBox "RS232 Communication" error $message
	    log_message "RS232 Communication time out."
	    updateGUI onRs232CommunicationOn
	    updateGUI onAnyCommunicationOff
	}
    } else {
	catch [unset ::sio::devId]
	updateGUI onRs232CommunicationOff
	updateGUI onAnyCommunicationOff
	set sync -3
	set message "The RS232 port could not be opened."
	messageBox "RS232 Communication" error $message
	log_message "RS232 Communication could not be opened."
    }
    #dbgEndProc [info level [info level]]
    return $sync
}
proc ptclCancelRs232Comm {} {
    #dbgBeginProc [info level [info level]]
    global flipStates
    if {[info exists ::sio::devId]} then {
	::sio::closeDevice
	updateGUI onRs232CommunicationOff
	updateGUI onAnyCommunicationOff
    }
    #dbgEndProc [info level [info level]]
    return
}
proc verifyChecksum {frame} {
    #dbgBeginProc [info level [info level]]
    set sum 0x00
    for {set i 1} {$i < [expr [string length $frame] - 2]} {incr i 2} {
	set byte [string range $frame $i [expr $i + 1]]
	set sum [format "%#04X" [expr $sum + 0x$byte]]
    }
    set cs [format %02X [expr [format "%#04X" [expr ~$sum + 0x01]] & 0xFF]]
    set frameCRC [string range $frame end-1 end]
    set status [string equal $cs $frameCRC]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclSendFrame {frame} {
    #dbgBeginProc [info level [info level]]
    global waitTime
    set ::sio::sioVars(AbortTx) 0
    ::sio::clearRxBuffer
    startTimeOutCounter $waitTime(standard)
    puts $::sio::devId $frame
    #dbgEndProc [info level [info level]]
    return $frame
}
proc ptclGetAck {t frame} {
    #dbgBeginProc [info level [info level]]
    global extraTimeOut errCode readframe sendframe retryPossible dongle ciError
    startExtraTimeOutCounter $t
    set status 1
    set errCode 0
    set sendframe $frame
    while {[string first "\n" $::sio::sioVars(RxBuffer)] == -1} {
	if {$extraTimeOut == -1} then {
	    set message "Time Out Error."
	    cmdsResetProgressBar
	    set errCode -10
	    set status 0
	    break
	}
	update
    }
    if {$status == 1} then {
	stopExtraTimeOutCounter
	set beginIndex [string first ":" $::sio::sioVars(RxBuffer)]
	set endIndex [string first "\n" $::sio::sioVars(RxBuffer)]
	set id [string range $frame 3 6]
	set speByte [string range $frame 7 8]
	set readframe [string range $::sio::sioVars(RxBuffer) $beginIndex [expr $endIndex-1]]
	set ::sio::sioVars(RxBuffer) [string replace $::sio::sioVars(RxBuffer) $beginIndex $beginIndex "!"]
	set ::sio::sioVars(RxBuffer) [string replace $::sio::sioVars(RxBuffer) $endIndex $endIndex "!"]
	set readId [string range $readframe 3 6]
	set readspeByte [string range $readframe 7 8]
	if {[verifyChecksum $readframe] == 1} then {
	    if {($readId == $id) &&($readspeByte == $speByte)} then {
		set status 1
	    } elseif {$readId == $ciError} {
		set message "Software Security Bit set.\n  Cannot access device data."
		set errCode -12
		set status 0
	    } elseif {$readId == $dongle} {
		set status -2
		#dbgShowInfo "getack -2 $retryPossible"
		if {$retryPossible == 0} then {
		    set message "Check sum error."
		    set errCode -15
		}
	    } else {
		set status 0
	    }
	} else {
	    set status -1
	    #dbgShowInfo "getack -1 $retryPossible"
	    if {$retryPossible == 0} then {
		set message "Check sum error."
		set errCode -15
	    }
	}
    }
    if {[info exists message]} then {
	messageBox "Communication Information" error $message
	cmdsResetProgressBar
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclUpdateOrCompareBuffer {addr6digit action} {
    #dbgBeginProc [info level [info level]]
    global readframe
    set addr 1
    set len 0x[string range $readframe 1 2]
    for {set i 0; set j 9} {$i < $len} {incr i; incr j 2} {
	if {$action == "update"} then {
	    writeBuffer [format "%06X" [expr $addr6digit + $i]] [string range $readframe $j [expr $j + 1]]
	} else {
	    set addr -1
	    if {[readBuffer [format "%06X" [expr $addr6digit + $i]]] != [string range $readframe $j [expr $j + 1]]} then {
		set addr [format "%#06X" [expr $addr6digit + $i]]
		set message "Memory Verify Fail at: $addr"
		log_message $message
		actionsLog_message "Memory Verify Fail at: $addr"
		cmdsResetProgressBar
		#dbgShowInfo "Verify FAIL."
		break
	    }
	}
    }
    #dbgEndProc [info level [info level]]
    return $addr
}
proc ptclSelectNode {} {
    #dbgBeginProc [info level [info level]]
    global flipStates atmelProtocol waitTime readframe
    global retryPossible dongle sendframe select_node canBaud
    set status 1
    set retryPossible 1
    set CRIS [format %08X 0x$::deviceArray(crisConnect)]
    set bitrate [format %04X [string range $canBaud 0 end-1]]
    set protocol "00"
    ptclInitDongle $bitrate $protocol $CRIS
    set frame [append frame ":01" $select_node "00" $::deviceArray(nnbConnect)]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    #dbgShowInfo "FRAME  > $frame"
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray(bootlId) [string range $readframe 9 10]
	set atmelProtocol(commState) [string range $readframe 11 12]
	if {$atmelProtocol(commState) == "01"} then {
	    if {[winfo exists .main.f_buffer.b_memSelect]} then {
		pack .main.f_buffer.b_memSelect -side bottom -expand 0 -pady 17
	    }
	    ptclReadBootlVer
	    updateGUI onAnyCommunicationOn
	    updateGUI onCanNodeSelectionOpened
	    log_message "CAN node $::deviceArray(nnbConnect) opened."
	} else {
	    if {[winfo exists .main.f_buffer.b_memSelect]} then {
		pack forget .main.f_buffer.b_memSelect
	    }
	    updateGUI onAnyCommunicationOff
	    updateGUI onCanNodeSelectionClosed
	    log_message "CAN node $::deviceArray(nnbConnect) closed."
	}
    } else {
	set flipStates(anyComm) "off"
	updateGUI onAnyCommunicationOff
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclSendIdProgStart {addLo addHi {memory "00"}} {
    #dbgBeginProc [info level [info level]]
    global buffer waitTime canProtocol prog_start retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":05" $prog_start "00" $memory [format %04X 0x$addLo] [format %04X 0x$addHi]]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    #dbgShowInfo "FRAME  > $frame"
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgramData {addLo addHi dummyArg} {
    #dbgBeginProc [info level [info level]]
    global waitTime temp prog_data readframe retryPossible dongle sendframe
    #dbgShowVar "addLo  > $addLo"
    #dbgShowVar "addHi  > $addHi"
    set retryPossible 1
    set len [format "%02X" [expr $addHi - $addLo + 1]]
    set frame [append frame ":" $len $prog_data "00"]
    for {set i $addLo} {$i <= $addHi} {incr i} {
	set frame ${frame}[readBuffer [format "%06X" $i]]
    }
    #dbgShowVar "frame = $frame"
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    #dbgShowInfo "FRAME  > $frame"
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	if {[string index $readframe end-2] == 0} then {
	    set status 1
	} elseif {[string index $readframe end-2] == 1} {
	    set status 0
	} elseif {[string index $readframe end-2] == 2} {
	    set status 2
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBlock {addrLo addrHi {memory "00"} {action "update"}} {
    #dbgBeginProc [info level [info level]]
    global waitTime display_data retryaddrLo protocol readframe retryPossible dongle sendframe
    set status 1
    set retryPossible 1
    set nbFrame [expr (($addrHi - $addrLo) / $protocol(frameLengthR)) +1]
    #dbgShowVar "nbFrame $nbFrame"
    set frame [append frame ":05" $display_data "00" $memory [format %04X $addrLo] [format %04X $addrHi]]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    while {$nbFrame !=0} {
	set status [ptclGetAck $waitTime(standard) $frame]
	if {$status == 1} then {
	    set failAddr [ptclUpdateOrCompareBuffer [format "%#06X" $addrLo] $action]
	    if {($failAddr == 1) ||($failAddr == -1)} then {
		set status 1
	    } else {
		set status 0
		break
	    }
	    #Frame is correctly read so we can read the following one
	    incr nbFrame -1
	    set addrLo [expr $addrLo + $protocol(frameLengthR)]
	} elseif {$retryPossible} {
	    if {$status == -2} then {
		set retryPossible 0
		set frame [append frame ":05" $display_data "00" $memory [format %04X $addrLo] [format %04X $addrHi]]
		set lFrame [list]
		for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
		    lappend lFrame [string range $frame $i [expr $i + 1]]
		}
		append frame [checkSum $lFrame]
		ptclSendFrame $frame
		set nbFrame [expr (($addrHi - $addrLo) / $protocol(frameLengthR)) +1]
	    } elseif {$status == -1} {
		set retryPossible 0
		set frame [append frame ":05" $display_data "00" $memory [format %04X $addrLo] [format %04X $addrHi]]
		set lFrame [list]
		for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
		    lappend lFrame [string range $frame $i [expr $i + 1]]
		}
		append frame [checkSum $lFrame]
		ptclSendFrame $frame
		set nbFrame [expr (($addrHi - $addrLo) / $protocol(frameLengthR)) +1]
	    } else {
		set status 0
		break
	    }
	} else {
	    set status 0
	    break
	}
	update
    }
    set status [expr $status==1]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclBlankCheck {addrLo addrHi {memory "01"}} {
    #dbgBeginProc [info level [info level]]
    global waitTime readframe display_data retryPossible dongle sendframe
    set retryPossible 1
    set waitTime(standard) 10000
    set frame [append frame ":05" $display_data "00" $memory [format %04X "0x$addrLo"] [format %04X "0x$addrHi"]]
    #dbgShowVar "assembled frame: $frame"
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    #dbgShowInfo "FRAME  > $frame"
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status == 1]
    }
    if {$status == 1} then {
	if {[string length $readframe] == 15} then {
	    set status [string range $readframe end-5 end-2]
	} else {
	    set status -1
	}
    }
    if {$status == 0} then {
	set status -2
    }
    set waitTime(standard) 3000
    #dbgShowVar "status $status"
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock0 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command sendframe retryPossible dongle
    set waitTime(standard) 10000
    set retryPossible 1
    set frame [append frame ":02" $write_command "000000"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    set waitTime(standard) 3000
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock1 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set waitTime(standard) 10000
    set frame [append frame ":02" $write_command "000020"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    set waitTime(standard) 3000
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock2 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set waitTime(standard) 10000
    set frame [append frame ":02" $write_command "000040"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    set waitTime(standard) 3000
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclFullChipErase {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set waitTime(standard) 10000
    set frame [append frame ":02" $write_command "0000FF"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    set loadConfig(programDevice) "setupProgramDevice"
    set waitTime(standard) 3000
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBSB {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000100" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteSBV {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000101" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgSSBlev1 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000105FE"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgSSBlev2 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000105FC"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteEB {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000106" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC1 {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "00011C" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC2 {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "00011D" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC3 {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "00011E" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteNNB {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "00011F" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteCRIS {data} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set frame [append frame ":03" $write_command "000120" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		#build the checksum frame: dongle is the command identifier 
		#of dongle and checksum  management    
		#sendframe is the penultimate sent  frame 
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteHwByte {{data "X"}} {
    #dbgBeginProc [info level [info level]]
    global write_command waitTime retryPossible dongle sendframe
    set retryPossible 1
    if {$data == "X"} then {
	set data [format %02X [expr [expr 0x$::deviceArray(hsb) & 0x3F] | [expr 0x$::deviceArray(x2Fuse) << 7] | [expr 0x$::deviceArray(bljbFuse) << 6]]]
    }
    set frame [append frame ":03" $write_command "000200" $data]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteHwReset {} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set status 1
    set frame [append frame ":02" $write_command "000300"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteLJMP {address} {
    #dbgBeginProc [info level [info level]]
    global waitTime write_command retryPossible dongle sendframe
    set retryPossible 1
    set status 1
    set frame [append frame ":04" $write_command "000301" $address]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBootlVer {} {
    #dbgBeginProc [info level [info level]]
    global waitTime rs232standard read_command readframe retryPossible dongle sendframe
    set p "bootlVer"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000000"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set c1 [string index $readframe end-3]
	set c2 [string index $readframe end-2]
	set ::deviceArray($p) "1.$c1.$c2"
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)" 
	setBootlVerDepFeatures "CAN" ${c1}${c2}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDevBootId1 {} {
    #dbgBeginProc [info level [info level]]
    global testFlag waitTime read_command readframe retryPossible dongle sendframe
    set p "deviceBootId1"
    set status 1
    set retryPossible 1
    if {$testFlag(readDevBootId1)} then {
	set frame [append frame ":02" $read_command "000001"]
	set lFrame [list]
	for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	    lappend lFrame [string range $frame $i [expr $i + 1]]
	}
	append frame [checkSum $lFrame]
	ptclSendFrame $frame
	set status [ptclGetAck $waitTime(standard) $frame]
	if {$status != 1} then {
	    if {$retryPossible} then {
		if {$status == -2} then {
		    set retryPossible 0
		    ptclSendFrame $frame
		    set status [ptclGetAck $waitTime(standard) $frame]
		} elseif {$status == -1} {
		    set retryPossible 0
		    set status [ptclChecksum]
		} else {
		    set status 0
		}
	    } else {
		set status 0
	    }
	    set status [expr $status==1]
	}
	if {$status == 1} then {
	    set ::deviceArray($p) [string range $readframe end-3 end-2]
	    #dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDevBootId2 {} {
    #dbgBeginProc [info level [info level]]
    global testFlag waitTime read_command readframe retryPossible dongle sendframe
    set p "deviceBootId2"
    set status 1
    set retryPossible 1
    if {$testFlag(readDevBootId2)} then {
	set frame [append frame ":02" $read_command "000002"]
	set lFrame [list]
	for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	    lappend lFrame [string range $frame $i [expr $i + 1]]
	}
	append frame [checkSum $lFrame]
	ptclSendFrame $frame
	set status [ptclGetAck $waitTime(standard) $frame]
	if {$status != 1} then {
	    if {$retryPossible} then {
		if {$status == -2} then {
		    set retryPossible 0
		    ptclSendFrame $frame
		    set status [ptclGetAck $waitTime(standard) $frame]
		} elseif {$status == -1} {
		    set retryPossible 0
		    set status [ptclChecksum]
		} else {
		    set status 0
		}
	    } else {
		set status 0
	    }
	    set status [expr $status==1]
	}
	if {$status == 1} then {
	    set ::deviceArray($p) [string range $readframe end-3 end-2]
	    #dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBSB {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "bsb"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000100"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadSBV {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "sbv"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000101"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadSSB {} {
    #dbgBeginProc [info level [info level]]
    global waitTime logFileId expAnsw read_command readframe retryPossible dongle sendframe
    set p "ssb"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000105"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
	set ::deviceArray(level) X
	foreach lev {0 1 2} {
	    foreach i $expAnsw(readSSBlev$lev) {
		if {$::deviceArray(ssb) == $i} then {
		    set ::deviceArray(level) $lev
		}
	    }
	}
	#dbgShowVar "::deviceArray(level) = $::deviceArray(level)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadEB {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "eb"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000106"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadManufId {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "manufId"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000130"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId1 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "deviceId1"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000131"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId2 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "deviceId2"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000160"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId3 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "deviceId3"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000161"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC1 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "btc1"
    set retryPossible 1
    set frame [append frame ":02" $read_command "00011C"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC2 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "btc2"
    set retryPossible 1
    set frame [append frame ":02" $read_command "00011D"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC3 {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "btc3"
    set retryPossible 1
    set frame [append frame ":02" $read_command "00011E"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadNNB {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p "nnbProg"
    set retryPossible 1
    set frame [append frame ":02" $read_command "00011F"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadCRIS {} {
    #dbgBeginProc [info level [info level]]
    global waitTime read_command readframe retryPossible dongle sendframe
    set p crisProg
    set retryPossible 1
    set frame [append frame ":02" $read_command "000120"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadHwByte {} {
    #dbgBeginProc [info level [info level]]
    global rs232standard waitTime read_command readframe retryPossible dongle sendframe
    set p "hsb"
    set retryPossible 1
    set frame [append frame ":02" $read_command "000200"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status != 1} then {
	if {$retryPossible} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set status [ptclChecksum]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set ::deviceArray($p) [string range $readframe end-3 end-2]
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)"
	set ::deviceArray(x2Fuse) [expr (0x$::deviceArray(hsb) | 0x7F) >> 7]
	set ::deviceArray(bljbFuse) [expr ((0x$::deviceArray(hsb) | 0xBF) & 0x7F) >> 6]
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclSetPortsConfig {} {
    #dbgBeginProc [info level [info level]]
    global bootloaderVerDependent
    global waitTime write_command retryPossible dongle sendframe
    set status 1
    if {$bootloaderVerDependent(p1p3p4_config)} then {
	set d0 01
	foreach p {p1 p3 p4} d1 {02 03 04} {
	    set retryPossible 1
	    set frame ""
	    set frame [append frame ":03" $write_command "00" $d0 $d1 $::deviceArray(${p}_config)]
	    set lFrame [list]
	    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
		lappend lFrame [string range $frame $i [expr $i + 1]]
	    }
	    append frame [checkSum $lFrame]
	    ptclSendFrame $frame
	    set status [ptclGetAck $waitTime(standard) $frame]
	    if {$status != 1} then {
		if {$retryPossible} then {
		    if {$status == -2} then {
			set retryPossible 0
			ptclSendFrame $frame
			set status [ptclGetAck $waitTime(standard) $frame]
		    } elseif {$status == -1} {
			set retryPossible 0
			set status [ptclChecksum]
		    } else {
			set status 0
		    }
		} else {
		    set status 0
		}
		set status [expr $status==1]
	    }
	    if {! $status} then {
		break
	    }
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadPortsConfig {} {
    #dbgBeginProc [info level [info level]]
    global bootloaderVerDependent
    global testFlag waitTime read_command readframe retryPossible dongle sendframe
    set status 1
    if {$bootloaderVerDependent(p1p3p4_config)} then {
	set d0 01
	foreach p {p1 p3 p4} d1 {02 03 04} {
	    set retryPossible 1
	    set frame ""
	    set frame [append frame ":02" $read_command "00" $d0 $d1]
	    set lFrame [list]
	    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
		lappend lFrame [string range $frame $i [expr $i + 1]]
	    }
	    append frame [checkSum $lFrame]
	    ptclSendFrame $frame
	    set status [ptclGetAck $waitTime(standard) $frame]
	    if {$status != 1} then {
		if {$retryPossible} then {
		    if {$status == -2} then {
			set retryPossible 0
			ptclSendFrame $frame
			set status [ptclGetAck $waitTime(standard) $frame]
		    } elseif {$status == -1} {
			set retryPossible 0
			set status [ptclChecksum]
		    } else {
			set status 0
		    }
		} else {
		    set status 0
		}
		set status [expr $status==1]
	    }
	    if {$status == 1} then {
		set ::deviceArray(${p}_config) [string range $readframe end-3 end-2]
		#dbgShowVar "::deviceArray(${p}_config) = \
			$::deviceArray(${p}_config)"	
	    } else {
		break
	    }
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclChecksum {} {
    #dbgBeginProc [info level [info level]]
    global waitTime dongle sendframe
    set status 1
    set frame [append frame1 ":00" $dongle "00"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $sendframe]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReset {} {
    #dbgBeginProc [info level [info level]]
    global waitTime dongle
    set status 1
    set frame [append frame ":00" $dongle "01"]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclInitDongle {bitrate protocol CRIS} {
    #dbgBeginProc [info level [info level]]
    global waitTime readframe dongle sendframe retryPossible
    set status 1
    set retryPossible 1
    set frame [append frame ":07" $dongle "02" $bitrate $protocol $CRIS]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    append frame [checkSum $lFrame]
    ptclSendFrame $frame
    set status [ptclGetAck $waitTime(standard) $frame]
    #dbgShowInfo "status $status"   
    if {$status != 1} then {
	if {$retryPossible==1} then {
	    if {$status == -2} then {
		set retryPossible 0
		ptclSendFrame $frame
		set status [ptclGetAck $waitTime(standard) $frame]
	    } elseif {$status == -1} {
		set retryPossible 0
		set frame1 [append frame1 ":00" $dongle "0002"]
		ptclSendFrame $frame1
		set status [ptclGetAck $waitTime(standard) $sendframe]
	    } else {
		set status 0
	    }
	} else {
	    set status 0
	}
	set status [expr $status==1]
    }
    if {$status == 1} then {
	set status [string range $readframe end-2 end-2]
    }
    if {$status==1} then {
	log_message "Dongle initialized"
	log_message "File > Load..."
    } else {
	log_message "Dongle Initialization Failed"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclStartBootloader {num_chip} {
    #dbgBeginProc [info level [info level]]
    global waitTime dongle
    set status 1
    set frame [append frame ":01" $dongle "03" $num_chip]
    set lFrame [list]
    for {set i 1} {$i <= [expr [string length $frame] - 2]} {incr i 2} {
	lappend lFrame [string range $frame $i [expr $i + 1]]
    }
    ptclSendFrame [append frame [checkSum $lFrame]]
    set status [ptclGetAck $waitTime(standard) $frame]
    if {$status == 1} then {
	if {[string range $readframe 9 10] == $num_chip} then {
	    set status 1
	} else {
	    set status 0
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclCheckCanEntries {} {
    set status 1
    if {! [isValidHexaInput $::deviceArray(nnbProg)]} then {
	set status 0
    }
    if {! [isValidHexaInput $::deviceArray(crisProg)]} then {
	set status 0
    }
    if {! [isValidHexaInput $::deviceArray(btc1)]} then {
	set status 0
    }
    if {! [isValidHexaInput $::deviceArray(btc2)]} then {
	set status 0
    }
    if {! [isValidHexaInput $::deviceArray(btc3)]} then {
	set status 0
    }
    return $status
}
proc ptclReadCanConfig {} {
    set status 0
    while {1} {
	if {! [ptclReadNNB]} then {
	    break
	}
	if {! [ptclReadCRIS]} then {
	    break
	}
	if {! [ptclReadBTC1]} then {
	    break
	}
	if {! [ptclReadBTC2]} then {
	    break
	}
	if {! [ptclReadBTC3]} then {
	    break
	}
	set status 1
	break
    }
    return $status
}
proc ptclSetCanConfig {} {
    set status 0
    while {1} {
	if {! [ptclCheckCanEntries]} then {
	    break
	}
	if {! [ptclWriteNNB $::deviceArray(nnbProg)]} then {
	    break
	}
	if {! [ptclWriteCRIS $::deviceArray(crisProg)]} then {
	    break
	}
	if {! [ptclWriteBTC1 $::deviceArray(btc1)]} then {
	    break
	}
	if {! [ptclWriteBTC2 $::deviceArray(btc2)]} then {
	    break
	}
	if {! [ptclWriteBTC3 $::deviceArray(btc3)]} then {
	    break
	}
	set status 1
	break
    }
    return $status
}
proc ptclStartAppli {reset_button} {
    #dbgBeginProc [info level [info level]]
    if {$reset_button} then {
	set status [ptclWriteHwReset]
    } else {
	set status [ptclWriteLJMP 0000]
    }
    updateGUI onAnyCommunicationOff
    updateGUI onCanNodeSelectionClosed
    #dbgEndProc [info level [info level]]
    return $status
}
#dbgEndSrc [info script]
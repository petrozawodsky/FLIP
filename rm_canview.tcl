#dbgBeginSrc [info script]
global atmelProtocol protocol
global cmd dongle cv
set cv(STB) "C"
set cv(SPB) [format %c 0X0A]
set atmelProtocol(ci_select_node) 0
set atmelProtocol(ci_prog_start) 1
set atmelProtocol(ci_prog_data) 2
set atmelProtocol(ci_display_data) 3
set atmelProtocol(ci_write_command) 4
set atmelProtocol(ci_read_command) 5
set atmelProtocol(ci_error) 6
set atmelProtocol(dongle) FFFF
set ::deviceArray(crisConnect) 00
set cmd(select_node) [format %04X [expr $atmelProtocol(ci_select_node) - 0x$::deviceArray(crisConnect)0]]
set cmd(prog_start) [format %04X [expr $atmelProtocol(ci_prog_start) - 0x$::deviceArray(crisConnect)0]]
set cmd(prog_data) [format %04X [expr $atmelProtocol(ci_prog_data) - 0x$::deviceArray(crisConnect)0]]
set cmd(display_data) [format %04X [expr $atmelProtocol(ci_display_data) - 0x$::deviceArray(crisConnect)0]]
set cmd(write_command) [format %04X [expr $atmelProtocol(ci_write_command) - 0x$::deviceArray(crisConnect)0]]
set cmd(read_command) [format %04X [expr $atmelProtocol(ci_read_command) - 0x$::deviceArray(crisConnect)0]]
set cmd(ciError) [format %04X [expr $atmelProtocol(ci_error) - 0x$::deviceArray(crisConnect)0]]
set dongle [format %04X 0x$atmelProtocol(dongle)]
if {! [info exists protocol(frameLengthW)]} then {
    set protocol(frameLengthW) 8
    set protocol(frameLengthR) 8
}
proc ptclInitComm {} {
    #dbgBeginProc [info level [info level]]
    global canBaud flipStates
    set status [ptclInitRs232Comm]
    if {$status == 1} then {
	set status [ptclInitDongle]
    } else {
	ptclCancelRs232Comm
	set status 0
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclInitRs232Comm {} {
    #dbgBeginProc [info level [info level]]
    global flipStates port baud baudList prot waitTime loadConfig projDir
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
	set sync 1
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
proc ptclSendFrame {frame} {
    #dbgBeginProc [info level [info level]]
    global waitTime
    set ::sio::sioVars(AbortTx) 0
    ::sio::clearRxBuffer
    startTimeOutCounter $waitTime(standard)
    puts -nonewline $::sio::devId $frame
    #dbgEndProc [info level [info level]]
    return $frame
}
proc ptclUpdateOrCompareBuffer {addr6digit action} {
    #dbgBeginProc [info level [info level]]
    global cv
    set addr 1
    set lineIdx 0
    while {[string length $::sio::sioVars(RxBuffer)] != 0} {
	set line [string range $::sio::sioVars(RxBuffer) 0 [string first $cv(SPB) $::sio::sioVars(RxBuffer) 0]]
	for {set i 5; set j 0} {[string range $line $i $i] != $cv(SPB)} {incr i 2; incr j 1} {
	    if {$action == "update"} then {
		writeBuffer [format "%06X" [expr $addr6digit + $lineIdx*8 + $j]] [string range $line $i [expr $i + 1]]
	    } else {
		set addr -1
		if {[readBuffer [format "%06X" [expr $addr6digit + $lineIdx*8 + $j]]] != [string range $line $i [expr $i + 1]]} then {
		    set addr [format "%#06X" [expr $addr6digit + $lineIdx*8 + $j]]
		    set message "Memory Verify Fail at: $addr"
		    log_message $message
		    actionsLog_message "Memory Verify Fail at: $addr"
		    cmdsResetProgressBar
		    #dbgShowInfo "Verify FAIL."
		    break
		}
	    }
	}
	if {($addr != -1) &&($addr != 1)} then {
	    break
	}
	set ::sio::sioVars(RxBuffer) [string replace $::sio::sioVars(RxBuffer) 0 [string first $cv(SPB) $::sio::sioVars(RxBuffer) 0]]
	incr lineIdx
    }
    #dbgEndProc [info level [info level]]
    return $addr
}
proc ptclSelectNode {} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    #dbgShowInfo "*********** Looping 50 times to clear the error counter ************"
    for {set i 0} {$i < 50} {incr i} {
	ptclSelectNod 0
	update
    }
    #dbgShowInfo "*********** End of clearing error counter loop ************"
    ptclSelectNod 1
    #dbgEndProc [info level [info level]]
    return
}
proc ptclSelectNod {displayCanError} {
    #dbgBeginProc [info level [info level]]
    global flipStates atmelProtocol waitTime readframe
    global dongle sendframe cmd canBaud cv
    set status 1
    set frame "${cv(STB)}${cmd(select_node)}"
    ptclSendFrame "${frame}${::deviceArray(nnbConnect)}${cv(SPB)}"
    if {! [getCmdEcho $frame 10 1000]} then {
	return 0
    }
    set tmp [string range $::sio::sioVars(RxBuffer) end-2 end-1]
    if {$displayCanError} then {
	if {[noCANviewError]} then {
	    set atmelProtocol(commState) $tmp
	    if {$atmelProtocol(commState) == "01"} then {
		if {[winfo exists .main.f_buffer.b_memSelect]} then {
		    pack .main.f_buffer.b_memSelect -side bottom -expand 0 -pady 17
		}
		ptclReadBootlVer
		updateGUI onAnyCommunicationOn
		updateGUI onCanNodeSelectionOpened
		log_message "CAN node $::deviceArray(nnbConnect) opened."
		#dbgShowInfo "CAN node $::deviceArray(nnbConnect) opened."
	    } else {
		if {[winfo exists .main.f_buffer.b_memSelect]} then {
		    pack forget .main.f_buffer.b_memSelect
		}
		updateGUI onAnyCommunicationOff
		updateGUI onCanNodeSelectionClosed
		log_message "CAN node $::deviceArray(nnbConnect) closed."
		#dbgShowInfo "CAN node $::deviceArray(nnbConnect) closed."
	    }
	} else {
	    set status 0
	    set flipStates(anyComm) "off"
	    updateGUI onAnyCommunicationOff
	}
    }
    #dbgShowVar "status = $status"
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclSendIdProgStart {addLo addHi {memory "00"}} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    set status 1
    set frame "${cv(STB)}${cmd(prog_start)}"
    set addrStr "[format %04X 0x$addLo][format %04X 0x$addHi]"
    ptclSendFrame "${frame}${memory}${addrStr}${cv(SPB)}"
    if {! [getCmdEcho $frame 0 1000]} then {
	set status 0
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgramData {addLo addHi dummyArg} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    set status 1
    set frame "${cv(STB)}${cmd(prog_data)}"
    set fullFrame $frame
    for {set i $addLo} {$i <= $addHi} {incr i} {
	set fullFrame ${fullFrame}[readBuffer [format "%06X" $i]]
    }
    #dbgShowVar "frame = $fullFrame"
    ptclSendFrame "${fullFrame}${cv(SPB)}"
    if {! [getCmdEcho $frame 8 3000]} then {
	return 0
    }
    set tmp [string range $::sio::sioVars(RxBuffer) end-2 end-1]
    if {$tmp == "00"} then {
	set status 1
    } elseif {$tmp == "01"} {
	set status 0
    } elseif {$tmp == "02"} {
	set status 2
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBlock {addrLo addrHi {memory "00"} {action "update"}} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    set status 1
    set mod [expr ($addrHi - $addrLo + 1) % 8]
    set nbFrames [expr ($addrHi - $addrLo + 1) / 8]
    if {$mod} then {
	set nbChars [expr ($nbFrames * (5+16+1)) + 5 + ($mod * 2) + 1]
    } else {
	set nbChars [expr $nbFrames * (5+16+1)]
    }
    #dbgShowVar "Expected number of chars = $nbChars"
    set addrStr "[format %04X $addrLo][format %04X $addrHi]"
    set frame "${cv(STB)}${cmd(display_data)}"
    ptclSendFrame "${frame}${memory}${addrStr}${cv(SPB)}"
    if {! [getCmdEcho $frame $nbChars 4000]} then {
	return 0
    }
    set failAddr [ptclUpdateOrCompareBuffer [format "%#06X" $addrLo] $action]
    if {($action == "compare") &&($failAddr != -1)} then {
	set status 0
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclBlankCheck {addrLo addrHi {memory "01"}} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    set status -1
    set addrStr [format %04X "0x$addrLo"][format %04X "0x$addrHi"]
    set frame "${cv(STB)}${cmd(display_data)}"
    ptclSendFrame "${frame}${memory}${addrStr}${cv(SPB)}"
    if {! [getCmdEcho $frame 0 4000]} then {
	set status -2
    } else {
	set tmpStr $::sio::sioVars(RxBuffer)
	if {! [noCANviewError]} then {
	    set status -2
	} elseif {[string length $tmpStr] == 10} {
	    set status [string range $tmpStr end-4 end-1]
	}
    }
    #dbgShowVar "ptclBlankCheck status = $status"
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock0 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte "" "0000" 3000]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock1 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte "" "0020" 3000]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclEraseBlock2 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte "" "0040" 3000]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclFullChipErase {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte "" "00FF" 10000]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteByte {data cmdBytes {timeOut 1000}} {
    #dbgBeginProc [info level [info level]]
    global cv cmd
    set status 1
    set frame "${cv(STB)}${cmd(write_command)}"
    ptclSendFrame "${frame}${cmdBytes}${data}${cv(SPB)}"
    if {! [getCmdEcho $frame 8 $timeOut]} then {
	set status 0
    } elseif {! [noCANviewError]} {
	set status 0
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBSB {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "0100"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteSBV {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "0101"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgSSBlev1 {} {
    #dbgBeginProc [info level [info level]]
    global expAnsw
    set status [ptclWriteByte $expAnsw(readSSBlev1Test) "0105"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclProgSSBlev2 {} {
    #dbgBeginProc [info level [info level]]
    global expAnsw
    set status [ptclWriteByte $expAnsw(readSSBlev2Test) "0105"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteEB {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "0106"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC1 {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "011C"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC2 {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "011D"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteBTC3 {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "011E"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteNNB {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "011F"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteCRIS {data} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "0120"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteHwByte {{data "X"}} {
    #dbgBeginProc [info level [info level]]
    if {$data == "X"} then {
	set data [format %02X [expr [expr 0x$::deviceArray(hsb) & 0x3F] | [expr 0x$::deviceArray(x2Fuse) << 7] | [expr 0x$::deviceArray(bljbFuse) << 6]]]
    }
    set status [ptclWriteByte $data "0200"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteHwReset {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $data "0300"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclWriteLJMP {address} {
    #dbgBeginProc [info level [info level]]
    set status [ptclWriteByte $address "0301"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclSetPortsConfig {} {
    #dbgBeginProc [info level [info level]]
    global bootloaderVerDependent
    set status 1
    if {$bootloaderVerDependent(p1p3p4_config)} then {
	set d0 01
	foreach p {p1 p3 p4} d1 {02 03 04} {
	    if {! [ptclWriteByte $::deviceArray(${p}_config) ${d0}${d1}]} then {
		set status 0
		break
	    }
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBootlVer {} {
    #dbgBeginProc [info level [info level]]
    global cv flipStates cmd
    set status 1
    set p bootlVer
    set frame "${cv(STB)}${cmd(read_command)}"
    ptclSendFrame "${frame}0000${cv(SPB)}"
    if {! [getCmdEcho $frame 8 1000]} then {
	return 0
    }
    set tmp [string range $::sio::sioVars(RxBuffer) end-2 end-1]
    if {[noCANviewError]} then {
	set c1 [string index $tmp end-1]
	set c2 [string index $tmp end]
	set ::deviceArray($p) "1.$c1.$c2"
	#dbgShowVar "::deviceArray($p) = $::deviceArray($p)" 
	setBootlVerDepFeatures "CAN" ${c1}${c2}
    } else {
	set status 0
	set flipStates(anyComm) "off"
	updateGUI onAnyCommunicationOff
    }
    #dbgShowVar "status = $status"
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDevBootId1 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "deviceBootId1" "0001"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDevBootId2 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "deviceBootId2" "0002"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBSB {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "bsb" "0100"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadSBV {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "sbv" "0101"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadSSB {} {
    #dbgBeginProc [info level [info level]]
    global expAnsw
    set status [ptclreadByte "ssb" "0105"]
    set ::deviceArray(level) X
    foreach lev {0 1 2} {
	foreach i $expAnsw(readSSBlev$lev) {
	    if {$::deviceArray(ssb) == $i} then {
		set ::deviceArray(level) $lev
	    }
	}
    }
    updateGUI onSecurityLevelChange
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadEB {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "eb" "0106"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadManufId {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "manufId" "0130"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId1 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "deviceId1" "0131"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId2 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "deviceId2" "0160"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadDeviceId3 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "deviceId3" "0161"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC1 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "btc1" "011C"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC2 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "btc2" "011D"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadBTC3 {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "btc3" "011E"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadNNB {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "nnbProg" "011F"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadCRIS {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "crisProg" "0120"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadHwByte {} {
    #dbgBeginProc [info level [info level]]
    set status [ptclreadByte "hsb" "0200"]
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclReadPortsConfig {} {
    #dbgBeginProc [info level [info level]]
    global bootloaderVerDependent cv flipStates cmd
    set status 1
    if {$bootloaderVerDependent(p1p3p4_config)} then {
	set d0 01
	foreach p {p1 p3 p4} d1 {02 03 04} {
	    set frame "${cv(STB)}${cmd(read_command)}${d0}${d1}"
	    ptclSendFrame "${frame}${cv(SPB)}"
	    if {! [getCmdEcho $frame 8 1000]} then {
		set status 0
		break
	    }
	    set tmp [string range $::sio::sioVars(RxBuffer) end-2 end-1]
	    if {[noCANviewError]} then {
		set ::deviceArray(${p}_config) $tmp
		#dbgShowVar "::deviceArray(${p}_config) = $::deviceArray(${p}_config)" 
	    } else {
		set status 0
		set flipStates(anyComm) "off"
		updateGUI onAnyCommunicationOff
		break
	    }
	}
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc getCmdEcho {echo length timeOut} {
    #dbgBeginProc [info level [info level]]
    global cv extraTimeOut errCode
    set extraTimeOut 1
    set status 1
    set errCode 0
    startExtraTimeOutCounter $timeOut
    if {$length == 0} then {
	while {([string first "$echo" $::sio::sioVars(RxBuffer)] == -1) &&([string first "C0006" $::sio::sioVars(RxBuffer)] == -1)} {
	    if {$extraTimeOut == -1} then {
		set status 0
		break
	    }
	    update
	}
    } else {
	while {([string length $::sio::sioVars(RxBuffer)] < $length) &&([string first "C0006" $::sio::sioVars(RxBuffer)] == -1)} {
	    if {$extraTimeOut == -1} then {
		set status 0
		break
	    }
	    update
	}
    }
    if {$status} then {
	stopExtraTimeOutCounter
	if {[string first "C0006" $::sio::sioVars(RxBuffer)] == 0} then {
	    cmdsResetProgressBar
	    set status 0
	    set errCode -12
	    messageBox "CANview message" error "Security bit set.\nCannot access device memory."
	}
    } else {
	cmdsResetProgressBar
	set errCode -10
	messageBox "CANview message" error "Time out error.\nFLIP and CANview baud rates  may not match.\n"
    }
    #dbgEndProc [info level [info level]]
    return $status
}
proc noCANviewError {} {
    #dbgBeginProc [info level [info level]]
    global cv
    set status 1
    set frame "${cv(STB)}8"
    ptclSendFrame "${frame}${cv(SPB)}"
    while {[string length $::sio::sioVars(RxBuffer)] < 5} {
	if {$::sio::sioVars(SerialEventOccured) == -1} then {
	    cmdsResetProgressBar
	    set status 0
	    messageBox "CANview message" error "Time out error.\nFLIP and CANview baud rates  may not match.\n"
	    break
	}
	update
    }
    if {$status} then {
	set status 0
	set errStatus [string range $::sio::sioVars(RxBuffer) 2 3]
	switch $errStatus {
	"01" {
		set message "CAN Buffer Overflow."
	    }
	"02" {
		set message "CAN Transmit Timeout."
	    }
	"04" {
		set message "CAN Error Counter Overflow."
	    }
	"08" {
		set message "CAN Bus-Off Error."
	    }
	"10" {
		set message "RS232 Syntax Error."
	    }
	"20" {
		set message "RS232 Format Error."
	    }
	"40" {
		set message "RS232 Buffer Overflow."
	    }
	default {
		set status 1
	    }
	}
	if {! $status} then {
	    messageBox "CANview Message" error "${message}\n FLIP will attempt to  reset the error status."
	    set frame "${cv(STB)}A"
	    ptclSendFrame "${frame}${cv(SPB)}"
	}
    }
    #dbgShowVar "status = $status"
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclInitDongle {} {
    #dbgBeginProc [info level [info level]]
    global canBaud cv
    set status 1
    set frame "${cv(STB)}E"
    ptclSendFrame "${frame}${cv(SPB)}"
    set status [getCmdEcho $frame 0 1000]
    if {$status} then {
	updateGUI onRs232CommunicationOn
	updateGUI onAnyCommunicationOff
	updateGUI onCanCommStatusModified
	switch $canBaud {
	20k {
		set frame "${cv(STB)}62101"
	    }
	125k {
		set frame "${cv(STB)}62103"
	    }
	250k {
		set frame "${cv(STB)}62104"
	    }
	500k {
		set frame "${cv(STB)}62105"
	    }
	1000k {
		set frame "${cv(STB)}62107"
	    }
	default {
		messageBox "CANview Message" warning "The selected bit rate is not supported by CANview."
		set status 0
	    }
	}
	if {$status} then {
	    ptclSendFrame "${frame}${cv(SPB)}"
	    if {! [getCmdEcho $frame 0 1000]} then {
		set status 0
	    }
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
proc ptclStartAppli {reset} {
    #dbgBeginProc [info level [info level]]
    if {$reset} then {
	set status [ptclWriteHwReset]
    } else {
	set status [ptclWriteLJMP 0000]
    }
    updateGUI onAnyCommunicationOff
    updateGUI onCanNodeSelectionClosed
    #dbgEndProc [info level [info level]]
    return $status
}
proc ptclreadByte {parameter cmdBytes} {
    #dbgBeginProc [info level [info level]]
    global cv flipStates cmd
    set status 1
    set frame "${cv(STB)}${cmd(read_command)}"
    ptclSendFrame "${frame}${cmdBytes}${cv(SPB)}"
    if {! [getCmdEcho $frame 8 1000]} then {
	return 0
    }
    set tmp [string range $::sio::sioVars(RxBuffer) end-2 end-1]
    if {[noCANviewError]} then {
	set ::deviceArray($parameter) $tmp
	#dbgShowVar "::deviceArray($parameter) = $::deviceArray($parameter)" 
    } else {
	set status 0
	set flipStates(anyComm) "off"
	updateGUI onAnyCommunicationOff
    }
    #dbgShowVar "status = $status"
    #dbgEndProc [info level [info level]]
    return $status
}
#dbgEndSrc [info script]
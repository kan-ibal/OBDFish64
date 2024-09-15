/*
 * Copyright (C) 2016 Jens Drescher, Germany
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.0
import Sailfish.Silica 1.0
import "SharedResources.js" as SharedResources
import "OBDDataObject.js" as OBDDataObject


Page
{
    id: id_page_mainpage

    property bool bFirstPage: true
    property bool bWaitForCommandSequenceEnd: false
    property int iInit: 0
    property int iWaitForCommand: 0
    property bool bBluetoothScanning: false
    property string sCurrentBTAddress: ""
    property string sCurrentBTName: ""
    property int iScannedDevicesCount: 0
    property int iUsedDevicesCount: 0

    onStatusChanged:
    {
        if (status === PageStatus.Active && bFirstPage)
        {
            bFirstPage = false

            //Load project data
            var sGetPIDsPage1 = id_ProjectSettings.sLoadProjectData("PIDsPage1");
            var sGetPIDsPage2 = id_ProjectSettings.sLoadProjectData("PIDsPage2");
            var sGetPIDsPage3 = id_ProjectSettings.sLoadProjectData("PIDsPage3");
            var sGetUsedAdaptersNames = id_ProjectSettings.sLoadProjectData("UsedAdaptersNames");
            var sGetUsedAdaptersAddresses = id_ProjectSettings.sLoadProjectData("UsedAdaptersAddresses");
            var sGetSaveDataToDebugFile = id_ProjectSettings.sLoadProjectData("WriteDebugFile");
            var sGetDoNotShowDTCWarning = id_ProjectSettings.sLoadProjectData("DoNotShowDTCWarning");

            console.log("sGetPIDsPage1" + sGetPIDsPage1);
            console.log("sGetPIDsPage2" + sGetPIDsPage2);
            console.log("sGetPIDsPage3" + sGetPIDsPage3);

            //DEBUG TODO
            //sGetUsedAdaptersNames = "Neuer Adapter v1.5#,#Adapter v2.1#,#Alter Adapter v1.5";
            //sGetUsedAdaptersAddresses = "12:34:56:88:C7:B1#,#88:18:56:68:98:EB#,#98:76:54:32:10:00";

            //Check project data
            if (sGetPIDsPage1.length > 0 && sGetPIDsPage2.length > 0 && sGetPIDsPage3.length > 0)
            {
                //Save loaded configuration to global array variable
                //For stupid crap QML arrays, have to use a JS array as middle man...
                var arTempArray = arPIDsPagesArray;

                arTempArray[0] = sGetPIDsPage1;
                arTempArray[1] = sGetPIDsPage2;
                arTempArray[2] = sGetPIDsPage3;

                arPIDsPagesArray = arTempArray;
            }

            if (sGetSaveDataToDebugFile.length > 0) bSaveDataToDebugFile=(sGetSaveDataToDebugFile === "true");

            if (sGetDoNotShowDTCWarning.length > 0) bDoNotShowDTCWarning=(sGetDoNotShowDTCWarning === "true");

            //Check if there are used devices. If there are, show them.
            if (sGetUsedAdaptersNames.length > 0 && sGetUsedAdaptersAddresses.length > 0)
            {
                 SharedResources.fncFillUsedAdaptersArray(sGetUsedAdaptersNames, sGetUsedAdaptersAddresses);
                id_LV_UsedDevices.model = iUsedDevicesCount = SharedResources.fncGetUsedDevicesNumber();
            }

            //Init debug file. Save first string.
            if (bSaveDataToDebugFile) id_FileWriter.vWriteStart("Version: " + Qt.application.version + "\r\n" + "Date: " + Date() + "\r\n-------------------------------\r\n");
        }
    }

    Connections
    {
        target: id_BluetoothConnection
        onDeviceFound:      //This is called from C++ if a bluetooth device was found
        {
            //Add device to data array
            SharedResources.fncAddDevice(sName, sAddress);
            id_LV_Devices.model = iScannedDevicesCount = SharedResources.fncGetDevicesNumber();
        }
        onScanFinished:
        {
            //Scan is finished now
            bBluetoothScanning = false;
        }
    }
    Connections
    {
        target: id_BluetoothData        
        onSigConnected:         //This is called from C++ if a connection was established
        {            
            bConnected = true;
            bConnecting = false;

            //Now start with initialize process
            iInit = 1;
            progressBarInit.label = qsTr("Checking OBD adapter...");

            //Send command to check if this is an ELM327
            iWaitForCommand = 0;
            fncStartCommand("ATZ");
            bWaitForCommandSequenceEnd = true;
        }
        onSigDisconnected:      //This is called from C++ if an established bluetooth connection gets disconnected
        {
            fncViewMessage("info", qsTr("Disconnected from adapter"));
            bConnected = false;
            bConnecting = false;

            sCoverValue1 = "";
            sCoverValue2 = "";
            sCoverValue3 = "";
        }
        onSigError:             //This is called from C++ if there was an error while establishing a bluetooth connection
        {
            fncShowMessage(3, qsTr("Error while connecting: ") + sError, 8000);
            bConnected = false;
            bConnecting = false;
        }
    }

    Timer
    {
        //This is called, everytime an AT command is send.
        //The timer waits for ELM to answer the command.
        id: timWaitForCommandSequenceEnd
        interval: 350
        running: bWaitForCommandSequenceEnd
        repeat: true
        onTriggered:
        {
            //Check if ELM has answered correctly to current AT command
            if (bCommandRunning == false)
            {
                iWaitForCommand = 0;
            
                console.log("timWaitForCommandSequenceEnd step:  " + iInit);

                //Init first step. This is after sending ATZ
                if (iInit == 1)
                {
                    //Get rid of all the carriage returns
                    var sAnswer = sReceiveBuffer.replace(/\r/g, " ");

                    //Check if this is an ELM327
                    if (sAnswer.indexOf("ELM327") === -1)
                    {
                        //This is not ELM327!!!
                        //Skip now and disconect from bluetooth device
                        fncShowMessage(3, qsTr("Error: unknown adapter. This is no ELM327 device!"), 8000);
                        id_BluetoothData.disconnect();
                        bWaitForCommandSequenceEnd = false;
                        iInit = 0;
                    }
                    else
                    {
                        //Now, this is an ELM327. So far so good.
                        //Extract the version number.
                        sELMVersion = (sAnswer.substr(sReceiveBuffer.indexOf(" v"))).trim();
                        
                        //Let's initialize this baby...
                        iInit = 2;
                        progressBarInit.label = qsTr("Switch echo off...");
                        fncStartCommand("ATE0");
                    }
                }
                else if (iInit == 2)
                {
                    //Just send next init command
                    iInit = 3;
                    progressBarInit.label = qsTr("Switch linefeed off...");
                    fncStartCommand("ATL0");
                }
                else if (iInit == 3)
                {
                    iInit = 4;
                    progressBarInit.label = qsTr("Switch headers off...");
                    fncStartCommand("ATH0");
                }
                else if (iInit == 4)
                {
                    iInit = 5;
                    progressBarInit.label = qsTr("Switch echo off...");
                    //fncStartCommand("ATS0");    //don't switch spaces off, old ELM's can't so this either!!!
                    fncStartCommand("ATE0");    //better repeat switching echo off. because this is really important.
                }
                else if (iInit == 5)
                {
                    iInit = 6;
                    progressBarInit.label = qsTr("Set protocol...");
                    fncStartCommand("ATSP0");
                }
                else if (iInit == 6)
                {
                    iInit = 7;
                    progressBarInit.label = qsTr("Supported PID's 0101-0120...");
                    fncStartCommand("0100");
                }
                else if (iInit == 7)
                {
                    iInit = 8;
                    OBDDataObject.fncSetSupportedPIDs(sReceiveBuffer, "0100");

                    progressBarInit.label = qsTr("Supported PID's 0121-0140...");
                    fncStartCommand("0120");
                }
                else if (iInit == 8)
                {
                    iInit = 9;
                    OBDDataObject.fncSetSupportedPIDs(sReceiveBuffer, "0120");

                    progressBarInit.label = qsTr("Supported PID's 0141-0160...");
                    fncStartCommand("0140");
                }
                else if (iInit == 9)
                {
                    iInit = 10;
                    //Evaluate answer from ELM
                    OBDDataObject.fncSetSupportedPIDs(sReceiveBuffer, "0140");

                    progressBarInit.label = qsTr("Supported PID's 0900-0920...");
                    fncStartCommand("0900");
                }
                else if (iInit == 10)
                {
                    iInit = 11;
                    //Evaluate answer from ELM
                    OBDDataObject.fncSetSupportedPIDs(sReceiveBuffer, "0900");

                    //Finish for now
                    bWaitForCommandSequenceEnd = false;

                    //Evaluate if ELM found any supported PID
                    if (OBDDataObject.fncGetFoundSupportedPIDs())
                    {
                        fncShowMessage(2,qsTr("Successfully connected to car computer!"), 6000);

                        //Save supported PID's to debug file
                        if (bSaveDataToDebugFile) id_FileWriter.vWriteData("Supported PID's 0100: " + OBDDataObject.sSupportedPIDs0100 + "\r\nSupported PID's 0900: " + OBDDataObject.sSupportedPIDs0900 + "\r\n");

                        //Save adapter as used adapter. Only do this if the adapter is not in the list of used devies.
                        if (sCurrentBTAddress !== "" && SharedResources.fncAddUsedDevice(sCurrentBTName, sCurrentBTAddress))
                        {
                            var sGetUsedAdaptersNames = id_ProjectSettings.sLoadProjectData("UsedAdaptersNames");
                            var sGetUsedAdaptersAddresses = id_ProjectSettings.sLoadProjectData("UsedAdaptersAddresses");

                            id_ProjectSettings.vSaveProjectData("UsedAdaptersNames", SharedResources.fncGetUsedDeviceBTNamesSeparatedString());
                            id_ProjectSettings.vSaveProjectData("UsedAdaptersAddresses", SharedResources.fncGetUsedDeviceBTAddressesSeparatedString());
                        }

                        iInit = 0;
                    }
                    else
                    {                       
                        fncShowMessage(0,qsTr("No supported PID's found!<br>- turn on ignition/engine<br>- reconnect to OBD adapter"), 20000);
                        id_BluetoothData.disconnect();
                        bWaitForCommandSequenceEnd = false;
                        iInit = 0;
                    }
                }
            }
            else
            {
                //ELM has not yet answered. Or the answer is not complete.
                //Check if wait time is over.
                if (iWaitForCommand == 40)
                {
                    //Now it depends on which command we are waiting.                                       
                    if (iInit == 1)
                    {
                        //If we wait for ELM to identify itself, break and disconnect.                        
                        fncViewMessage("error", "Unknown OBD Adapter!!!");
                        iInit = 0; 
                    }
                    else if (iInit > 1)
                    {
                        //If we are in init procedure, reset init progress
                        iInit = 0; 
                    }                    
                    
                    //Skip now and disconect from bluetooth device                       
                    bWaitForCommandSequenceEnd = false;                        
                    fncViewMessage("error", "Communication timeout!!!");
                    id_BluetoothData.disconnect();                                        
                }
                else
                    iWaitForCommand++;
            }            
        }
    }


    // To enable PullDownMenu, place our content in a SilicaFlickable
    SilicaFlickable
    {
        anchors.fill: parent
        contentHeight: id_Column_FirstCol.height + Theme.paddingLarge;

        PullDownMenu
        {
            MenuItem
            {
                text: qsTr("About")
                onClicked: {pageStack.push(Qt.resolvedUrl("AboutPage.qml"))}
            }
            MenuItem
            {
                text: qsTr("Settings")
                onClicked: {pageStack.push(Qt.resolvedUrl("GeneralSettingsPage.qml"))}
            }                        
        }       

        Column
        {
            id: id_Column_FirstCol

            width: parent.width
            spacing: Theme.paddingLarge
            PageHeader 
            {
                title: qsTr("Welcome to OBDFish")
            }

            Image
            {
                visible: true
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width / 3.2
                height: (parent.width / 3.2) / 1.666666
                source: "../elm327.png"

                Item
                {
                    //color: "white"
                    width: parent.width / 14.1176
                    height: parent.width / 14.1176
                    anchors.top: parent.top
                    anchors.topMargin: parent.height / 2.4407
                    anchors.left: parent.left
                    anchors.leftMargin: parent.width / 6

                    GlassItem
                    {
                        id: id_GlassItem_Red
                        color: "red"
                        anchors.centerIn: parent
                        visible: (bConnecting || bConnected)
                        //visible: true
                    }
                }

                Item
                {
                    //color: "white"
                    width: parent.width / 14.1176
                    height: parent.width / 14.1176
                    anchors.top: parent.top
                    anchors.topMargin: parent.height / 1.6941
                    anchors.left: parent.left
                    anchors.leftMargin: parent.width / 6

                    GlassItem
                    {
                        id: id_GlassItem_Yellow
                        color: "yellow"
                        anchors.centerIn: parent
                        visible: (iInit > 0)
                        //visible: true
                        Timer
                        {
                            repeat: true
                            running: (iInit > 0)
                            interval: 250
                            onTriggered: id_GlassItem_Yellow.id_GlassItem_Reddimmed = !id_GlassItem_Yellow.dimmed
                        }
                    }
                }

                Item
                {
                    //color: "white"
                    width: parent.width / 14.1176
                    height: parent.width / 14.1176
                    anchors.top: parent.top
                    anchors.topMargin: parent.height / 1.2743
                    anchors.left: parent.left
                    anchors.leftMargin: parent.width / 6

                    GlassItem
                    {
                        id: id_GlassItem_Green
                        color: "#03EC16"
                        anchors.centerIn: parent
                        visible: (iInit > 0)
                        //visible: true
                        Timer
                        {
                            repeat: true
                            running: (iInit > 0)
                            interval: 100
                            onTriggered: id_GlassItem_Green.dimmed = !id_GlassItem_Green.dimmed
                        }
                    }
                }
            }           
            SectionHeader
            {
                text: qsTr("Scan for Bluetooth devices...")
                visible: !bBluetoothScanning && !bConnecting && !bConnected
            }
            Button
            {
                width: parent.width
                text: qsTr("Start Scanning...")
                visible: !bBluetoothScanning && !bConnecting && !bConnected
                onClicked:
                {                    
                    bBluetoothScanning = true;
                    SharedResources.fncDeleteDevices();
                    id_LV_Devices.model = iScannedDevicesCount = SharedResources.fncGetDevicesNumber();
                    id_BluetoothConnection.vStartDeviceDiscovery();
                }
                Image
                {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-bluetooth"
                }
            }
            Button
            {
                width: parent.width
                text: qsTr("Cancel")
                visible: bBluetoothScanning
                onClicked:
                {
                    id_BluetoothConnection.vStopDeviceDiscovery();
                }
                Image
                {
                    source: "image://theme/icon-m-sync"
                    anchors.verticalCenter: parent.verticalCenter
                    smooth: true
                    NumberAnimation on rotation
                    {
                      running: bBluetoothScanning
                      from: 0
                      to: 360
                      loops: Animation.Infinite
                      duration: 2000
                    }
                }
            }            
            Item
            {
                width: parent.width
                height: Theme.paddingLarge
            }
            Button
            {
                width: parent.width
                text: qsTr("General Informations")
                visible: (bConnected && !bConnecting && iInit === 0)
                onClicked: {pageStack.push(Qt.resolvedUrl("GeneralInfo.qml"))}
            }
            Separator {color: Theme.highlightColor; width: parent.width; visible: (bConnected && !bConnecting && iInit === 0);}
            Button
            {
                width: parent.width
                text: qsTr("Dynamic Values")
                visible: (bConnected && !bConnecting && iInit === 0)
                onClicked: {pageStack.push(Qt.resolvedUrl("Dyn1Page.qml"))}
            }
            Separator {color: Theme.highlightColor; width: parent.width; visible: (bConnected && !bConnecting && iInit === 0);}
            Button
            {
                width: parent.width
                text: qsTr("Error Informations")
                visible: (bConnected && !bConnecting && iInit === 0)
                onClicked: {pageStack.push(Qt.resolvedUrl("ErrorPage.qml"))}
            }
            Separator {color: Theme.highlightColor; width: parent.width; visible: (bConnected && !bConnecting && iInit === 0);}
            Button
            {
                width: parent.width
                text: qsTr("Disconnect")
                visible: (bConnected && !bConnecting && iInit === 0)
                onClicked:
                {
                    id_BluetoothData.disconnect();
                }
                Image
                {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-dismiss"
                }
            }

            SectionHeader
            {
                text: qsTr("Connecting:")
                visible: bConnecting
            }
            ProgressBar
            {
                id: progressBarConnectBT
                width: parent.width
                visible: bConnecting
                indeterminate: true
                label: qsTr("Connecting to OBD adapter...")
            }

            SectionHeader
            {
                text: qsTr("Initializing:")
                visible: (iInit > 0)
            }
            ProgressBar
            {
                id: progressBarInit
                width: parent.width
                maximumValue: 11
                valueText: value + "/" + maximumValue
                label: ""
                visible: (iInit > 0)
                value: iInit
            }

            SectionHeader
            {
                id: id_SH_UsedDevices
                text: qsTr("OBD adapters (press to connect):")
                visible: (iScannedDevicesCount === 0 && iUsedDevicesCount > 0 && !bConnected && !bConnecting && iInit === 0)
            }
            SilicaListView
            {
                id: id_LV_UsedDevices
                model: SharedResources.fncGetUsedDevicesNumber();
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height / 3
                visible: (iScannedDevicesCount === 0 && iUsedDevicesCount > 0 && !bConnected && !bConnecting && iInit === 0)

                delegate: BackgroundItem
                {
                    id: delegateUsedDevices

                    Label
                    {
                        x: Theme.paddingLarge
                        text: SharedResources.fncGetUsedDeviceBTName(index) + ", " + SharedResources.fncGetUsedDeviceBTAddress(index);
                        anchors.verticalCenter: parent.verticalCenter
                        color: delegateUsedDevices.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    onClicked:
                    {
                        //Connect here. Prepeare some things.
                        OBDDataObject.sSupportedPIDs0100 = "";
                        OBDDataObject.sSupportedPIDs0900 = "";
                        sELMVersion= "";
                        bConnecting = true;                                               

                        //Connect and init
                        id_BluetoothData.connect(SharedResources.fncGetUsedDeviceBTAddress(index), 1);
                    }
                }
                VerticalScrollDecorator {}
            }

            SectionHeader
            {
                id: id_SC_Devices
                text: qsTr("Found adapters (press to connect):")
                visible: (iScannedDevicesCount > 0 &&  !bConnected && !bConnecting && iInit === 0)
            }
            SilicaListView
            {
                id: id_LV_Devices
                model: SharedResources.fncGetDevicesNumber();
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height / 3
                visible: (iScannedDevicesCount > 0 &&  !bConnected && !bConnecting && iInit === 0)

                delegate: BackgroundItem
                {
                    id: delegateDevices

                    Label
                    {
                        x: Theme.paddingLarge
                        text: SharedResources.fncGetDeviceBTName(index) + ", " + SharedResources.fncGetDeviceBTAddress(index);
                        anchors.verticalCenter: parent.verticalCenter
                        color: delegateDevices.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    onClicked:
                    {
                        //Connect here. Prepeare some things.
                        OBDDataObject.sSupportedPIDs0100 = "";
                        OBDDataObject.sSupportedPIDs0900 = "";
                        sELMVersion= "";
                        bConnecting = true;

                        //Save chosen BT connection data to page variables
                        //They need to be saved in List of used devices. This will be done after successful initializing.
                        sCurrentBTAddress = SharedResources.fncGetDeviceBTAddress(index);
                        sCurrentBTName = SharedResources.fncGetDeviceBTName(index);

                        //Connect and init
                        id_BluetoothData.connect(SharedResources.fncGetDeviceBTAddress(index), 1);
                    }
                }
                VerticalScrollDecorator {}
            }                   
        }
    }
}

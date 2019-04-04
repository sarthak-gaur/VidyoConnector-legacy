function ShowRenderer(vidyoConnector) {
    var rndr = document.getElementById('renderer');
    vidyoConnector.ShowViewAt({viewId: "renderer", x: rndr.offsetLeft, y: rndr.offsetTop, width: rndr.offsetWidth, height: rndr.offsetHeight});
}

// Run StartVidyoConnector when the VidyoClient is successfully loaded
function StartVidyoConnector(VC, useTranscodingWebRTC, performMonitorShare, webrtcExtensionPath, configParams) {
    var vidyoConnector;
    var cameras = {};
    var microphones = {};
    var speakers = {};
    var cameraPrivacy = false;
    var microphonePrivacy = false;

    window.onresize = function()
    {
        ShowRenderer(vidyoConnector);
    };
    
    window.onbeforeunload = function() {
        vidyoConnector.Destruct();
    }

    VC.CreateVidyoConnector({
        viewId: "renderer",                            // Div ID where the composited video will be rendered, see VidyoConnector.html
        viewStyle: "VIDYO_CONNECTORVIEWSTYLE_Default", // Visual style of the composited renderer
        remoteParticipants: 8,                         // Maximum number of participants to render
        logFileFilter: "warning info@VidyoClient info@VidyoConnector",
        logFileName:"",
        userData:""
    }).then(function(vc) {
        vidyoConnector = vc;
        ShowRenderer(vidyoConnector);
        registerDeviceListeners(vidyoConnector, cameras, microphones, speakers);
        handleDeviceChange(vidyoConnector, cameras, microphones, speakers);
        handleParticipantChange(vidyoConnector);
        handleSharing(vidyoConnector, useTranscodingWebRTC, performMonitorShare, webrtcExtensionPath);

        // Populate the connectionStatus with the client version
        vidyoConnector.GetVersion().then(function(version) {
            $("#clientVersion").html("v " + version);
        }).catch(function() {
            console.error("GetVersion failed");
        });

        // If enableDebug is configured then enable debugging
        if (configParams.enableDebug === "1") {
            vidyoConnector.EnableDebug({port:7776, logFilter: "warning info@VidyoClient info@VidyoConnector"}).then(function() {
                console.log("EnableDebug success");
            }).catch(function() {
                console.error("EnableDebug failed");
            });
        }

        // If running on Internet Explorer, set the default certificate authority list.
        // This is necessary when IE's Protected Mode is enabled.
        if (configParams.isIE) {
            vidyoConnector.SetCertificateAuthorityList({ certificateAuthorityList: "default" }).then(function() {
                console.log("SetCertificateAuthorityList success");
            }).catch(function() {
                console.error("SetCertificateAuthorityList failed");
            });
        }

        // Handle camera privacy and microphone privacy initial state
        if (configParams.cameraPrivacy === "1") {
           $("#cameraButton").click();
        }
        if (configParams.microphonePrivacy === "1") {
           $("#microphoneButton").click();
        }

        // Join the conference if the autoJoin URL parameter was enabled
        if (configParams.autoJoin === "1") {
          joinLeave();
        } else {
          // Handle the join in the toolbar button being clicked by the end user.
          $("#joinLeaveButton").one("click", joinLeave);
        }

        // Handle the camera privacy button, toggle between show and hide.
        $("#cameraButton").click(function() {
            // CameraPrivacy button clicked
            cameraPrivacy = !cameraPrivacy;
            vidyoConnector.SetCameraPrivacy({
                privacy: cameraPrivacy
            }).then(function() {
                if (cameraPrivacy) {
                    $("#cameraButton").addClass("cameraOff").removeClass("cameraOn");
                } else {
                    $("#cameraButton").addClass("cameraOn").removeClass("cameraOff");
                }
                console.log("SetCameraPrivacy Success");
            }).catch(function() {
                console.error("SetCameraPrivacy Failed");
            });
        });

        // Handle the microphone mute button, toggle between mute and unmute audio.
        $("#microphoneButton").click(function() {
            // MicrophonePrivacy button clicked
            microphonePrivacy = !microphonePrivacy;
            vidyoConnector.SetMicrophonePrivacy({
                privacy: microphonePrivacy
            }).then(function() {
                if (microphonePrivacy) {
                    $("#microphoneButton").addClass("microphoneOff").removeClass("microphoneOn");
                } else {
                    $("#microphoneButton").addClass("microphoneOn").removeClass("microphoneOff");
                }
                console.log("SetMicrophonePrivacy Success");
            }).catch(function() {
                console.error("SetMicrophonePrivacy Failed");
            });
        });

        // Handle the options visibility button, toggle between show and hide options.
        $("#optionsVisibilityButton").click(function() {
            // OptionsVisibility button clicked
            if ($("#optionsVisibilityButton").hasClass("hideOptions")) {
                $("#options").addClass("hidden");
                $("#optionsVisibilityButton").addClass("showOptions").removeClass("hideOptions");
                $("#renderer").addClass("rendererFullScreen").removeClass("rendererWithOptions");
            } else {
                $("#options").removeClass("hidden");
                $("#optionsVisibilityButton").addClass("hideOptions").removeClass("showOptions");
                $("#renderer").removeClass("rendererFullScreen").addClass("rendererWithOptions");
            }
        });

        function joinLeave() {
            // join or leave dependent on the joinLeaveButton, whether it
            // contains the class callStart or callEnd.
            if ($("#joinLeaveButton").hasClass("callStart")) {
                $("#connectionStatus").html("Connecting...");
                $("#joinLeaveButton").removeClass("callStart").addClass("callEnd");
                $('#joinLeaveButton').prop('title', 'Leave Conference');
                connectToConference(vidyoConnector, configParams.returnURL);
            } else {
                $("#connectionStatus").html("Disconnecting...");
                vidyoConnector.Disconnect().then(function() {
                    console.log("Disconnect Success");
                }).catch(function() {
                    console.error("Disconnect Failure");
                });
            }
            $("#joinLeaveButton").one("click", joinLeave);
        }
    }).catch(function(err) {
        console.error("CreateVidyoConnector Failed " + err);
    });
}

function registerDeviceListeners(vidyoConnector, cameras, microphones, speakers) {
    // Map the "None" option (whose value is 0) in the camera, microphone, and speaker drop-down menus to null since
    // a null argument to SelectLocalCamera, SelectLocalMicrophone, and SelectLocalSpeaker releases the resource.
    cameras[0]     = null;
    microphones[0] = null;
    speakers[0]    = null;

    // Handle appearance and disappearance of camera devices in the system
    vidyoConnector.RegisterLocalCameraEventListener({
        onAdded: function(localCamera) {
            // New camera is available
            $("#cameras").append("<option value='" + window.btoa(localCamera.id) + "'>" + localCamera.name + "</option>");
            cameras[window.btoa(localCamera.id)] = localCamera;
        },
        onRemoved: function(localCamera) {
            // Existing camera became unavailable
            $("#cameras option[value='" + window.btoa(localCamera.id) + "']").remove();
            delete cameras[window.btoa(localCamera.id)];
        },
        onSelected: function(localCamera) {
            // Camera was selected/unselected by you or automatically
            if(localCamera) {
                $("#cameras option[value='" + window.btoa(localCamera.id) + "']").prop('selected', true);
            }
        },
        onStateUpdated: function(localCamera, state) {
            // Camera state was updated
        }
    }).then(function() {
        console.log("RegisterLocalCameraEventListener Success");
    }).catch(function() {
        console.error("RegisterLocalCameraEventListener Failed");
    });

    // Handle appearance and disappearance of microphone devices in the system
    vidyoConnector.RegisterLocalMicrophoneEventListener({
        onAdded: function(localMicrophone) {
            // New microphone is available
            $("#microphones").append("<option value='" + window.btoa(localMicrophone.id) + "'>" + localMicrophone.name + "</option>");
            microphones[window.btoa(localMicrophone.id)] = localMicrophone;
        },
        onRemoved: function(localMicrophone) {
            // Existing microphone became unavailable
            $("#microphones option[value='" + window.btoa(localMicrophone.id) + "']").remove();
            delete microphones[window.btoa(localMicrophone.id)];
        },
        onSelected: function(localMicrophone) {
            // Microphone was selected/unselected by you or automatically
            if(localMicrophone)
                $("#microphones option[value='" + window.btoa(localMicrophone.id) + "']").prop('selected', true);
        },
        onStateUpdated: function(localMicrophone, state) {
            // Microphone state was updated
        }
    }).then(function() {
        console.log("RegisterLocalMicrophoneEventListener Success");
    }).catch(function() {
        console.error("RegisterLocalMicrophoneEventListener Failed");
    });

    // Handle appearance and disappearance of speaker devices in the system
    vidyoConnector.RegisterLocalSpeakerEventListener({
        onAdded: function(localSpeaker) {
            // New speaker is available
            $("#speakers").append("<option value='" + window.btoa(localSpeaker.id) + "'>" + localSpeaker.name + "</option>");
            speakers[window.btoa(localSpeaker.id)] = localSpeaker;
        },
        onRemoved: function(localSpeaker) {
            // Existing speaker became unavailable
            $("#speakers option[value='" + window.btoa(localSpeaker.id) + "']").remove();
            delete speakers[window.btoa(localSpeaker.id)];
        },
        onSelected: function(localSpeaker) {
            // Speaker was selected/unselected by you or automatically
            if(localSpeaker)
                $("#speakers option[value='" + window.btoa(localSpeaker.id) + "']").prop('selected', true);
        },
        onStateUpdated: function(localSpeaker, state) {
            // Speaker state was updated
        }
    }).then(function() {
        console.log("RegisterLocalSpeakerEventListener Success");
    }).catch(function() {
        console.error("RegisterLocalSpeakerEventListener Failed");
    });
}

function handleDeviceChange(vidyoConnector, cameras, microphones, speakers) {
    // Hook up camera selector functions for each of the available cameras
    $("#cameras").change(function() {
        // Camera selected from the drop-down menu
        $("#cameras option:selected").each(function() {
            camera = cameras[$(this).val()];
            vidyoConnector.SelectLocalCamera({
                localCamera: camera
            }).then(function() {
                console.log("SelectCamera Success");
            }).catch(function() {
                console.error("SelectCamera Failed");
            });
        });
    });

    // Hook up microphone selector functions for each of the available microphones
    $("#microphones").change(function() {
        // Microphone selected from the drop-down menu
        $("#microphones option:selected").each(function() {
            microphone = microphones[$(this).val()];
            vidyoConnector.SelectLocalMicrophone({
                localMicrophone: microphone
            }).then(function() {
                console.log("SelectMicrophone Success");
            }).catch(function() {
                console.error("SelectMicrophone Failed");
            });
        });
    });

    // Hook up speaker selector functions for each of the available speakers
    $("#speakers").change(function() {
        // Speaker selected from the drop-down menu
        $("#speakers option:selected").each(function() {
            speaker = speakers[$(this).val()];
            vidyoConnector.SelectLocalSpeaker({
                localSpeaker: speaker
            }).then(function() {
                console.log("SelectSpeaker Success");
            }).catch(function() {
                console.error("SelectSpeaker Failed");
            });
        });
    });
}

function handleSharing(vidyoConnector, useTranscodingWebRTC, performMonitorShare, webrtcExtensionPath) {
    var monitorShares = {};
    var windowShares  = {};
    var isSharingWindow = false; // Flag indicating whether a window is currently being shared

    // The monitorShares & windowShares associative arrays hold a handle to each window/monitor that are available for sharing.
    // The element with key "0" contains a value of null, which is used to stop sharing.
    monitorShares[0] = null;
    windowShares[0]  = null;

    // In WebRTC (transcoding and native), monitor sharing is included as part of the window sharing API.
    if (performMonitorShare) {
        StartMonitorShare();
    }

    // Sharing functionality differs if Transcoding WebRTC is being used.
    if (!useTranscodingWebRTC) {
        StartWindowShare();
    } else {
        // In Transcoding WebRTC mode, StartWindowShare() needs to be called each time a new share
        // is initiated so perform this action when the "Window Share" drop-down list is clicked.
        $("#windowShares").mousedown(function() {
            console.log("*** Window Share drop-down clicked. isSharingWindow = " + isSharingWindow);

            // Initiate the share selection process only if not already sharing
            if (isSharingWindow === false) {
                // Re-initialize the windowShares array
                windowShares = {};
                windowShares[0] = null;

                // Clear all of the drop-down items other than the first ("None"), which is used to stop sharing
                $("#windowShares").find('option').not(':first').remove();

                // Start window sharing (in WebRTC mode, this includes monitors)
                StartWindowShare();
            }
        });
    }

    function StartWindowShare() {
        // Register for window share status updates, which operates differently in Transcoding WebRTC vs other modes:
        //    plugin: onAdded and onRemoved callbacks are received for each available window.
        //    native webrtc: onAdded callback received for a single item, which when clicked will yield a popup to select a share.
        //    transcoding webrtc: a popup is displayed (an extension to Firefox/Chrome) which allows the user to
        //            select a share; once selected, that share will trigger an onAdded event.
        vidyoConnector.RegisterLocalWindowShareEventListener({
            onAdded: function(localWindowShare) {
                // In useTranscodingWebRTC mode, select the share which triggered this callback
                if (useTranscodingWebRTC) {
                    vidyoConnector.SelectLocalWindowShare({
                        localWindowShare: localWindowShare
                    }).then(function() {
                        console.log("SelectLocalWindowShare Success");
                    }).catch(function() {
                        console.error("SelectLocalWindowShare Failed");
                    });
                }

                // New share is available so add it to the windowShares array and the drop-down list
                if (localWindowShare.name != "") {
                    var shareVal;
                    if (useTranscodingWebRTC) {
                        shareVal = "Selected Share";
                    } else {
                        shareVal = localWindowShare.applicationName + " : " + localWindowShare.name;
                    }
                    $("#windowShares").append("<option value='" + window.btoa(localWindowShare.id) + "'>" + shareVal + "</option>");
                    windowShares[window.btoa(localWindowShare.id)] = localWindowShare;
                    console.log("Window share added, name : " + localWindowShare.name + " | id : " + window.btoa(localWindowShare.id));
                }
            },
            onRemoved: function(localWindowShare) {
                // Existing share became unavailable
                $("#windowShares option[value='" + window.btoa(localWindowShare.id) + "']").remove();
                delete windowShares[window.btoa(localWindowShare.id)];
            },
            onSelected: function(localWindowShare) {
                // Share was selected/unselected by you or automatically
                if (localWindowShare) {
                    $("#windowShares option[value='" + window.btoa(localWindowShare.id) + "']").prop('selected', true);
                    isSharingWindow = true;
                    console.log("Window share selected : " + localWindowShare.name);
                } else {
                    $("#windowShares option[value='0']").prop('selected', true);
                    isSharingWindow = false;
                    console.log("Stop sharing window");
                }
            },
            onStateUpdated: function(localWindowShare, state) {
                // localWindowShare state was updated
            }
        }).then(function(result) {
            if (result) {
                console.log("RegisterLocalWindowShareEventListener Success");
            } else {
                console.error("RegisterLocalWindowShareEventListener Failed");
                if (webrtcExtensionPath.length === 0) {
                    alert("Error: cannot initiate window sharing.");
                } else {
                    prompt("An extension is needed to initiate window sharing. Navigate to the URL below to install.", webrtcExtensionPath);
                }
            }
        }).catch(function() {
            console.error("RegisterLocalWindowShareEventListener Failed");
        });
    }

    function StartMonitorShare() {
        // Register for monitor share status updates
        vidyoConnector.RegisterLocalMonitorEventListener({
            onAdded: function(localMonitorShare) {
                // New share is available so add it to the monitorShares array and the drop-down list
                if (localMonitorShare.name != "") {
                    $("#monitorShares").append("<option value='" + window.btoa(localMonitorShare.id) + "'>" + localMonitorShare.name + "</option>");
                    monitorShares[window.btoa(localMonitorShare.id)] = localMonitorShare;
                    console.log("Monitor share added, name : " + localMonitorShare.name + " | id : " + window.btoa(localMonitorShare.id));
                }
            },
            onRemoved: function(localMonitorShare) {
                // Existing share became unavailable
                $("#monitorShares option[value='" + window.btoa(localMonitorShare.id) + "']").remove();
                delete monitorShares[window.btoa(localMonitorShare.id)];
            },
            onSelected: function(localMonitorShare) {
                // Share was selected/unselected by you or automatically
                if (localMonitorShare) {
                    $("#monitorShares option[value='" + window.btoa(localMonitorShare.id) + "']").prop('selected', true);
                    console.log("Monitor share selected : " + localMonitorShare.name);
                }
            },
            onStateUpdated: function(localMonitorShare, state) {
                // localMonitorShare state was updated
            }
        }).then(function() {
            console.log("RegisterLocalMonitorShareEventListener Success");
        }).catch(function() {
            console.error("RegisterLocalMonitorShareEventListener Failed");
        });
    }

    // A monitor was selected from the "Monitor Share" drop-down list (plugin mode only).
    $("#monitorShares").change(function() {
        console.log("*** Monitor shares change called");

        // Find the share selected from the drop-down list
        $("#monitorShares option:selected").each(function() {
            share = monitorShares[$(this).val()];

            // Select the local monitor
            vidyoConnector.SelectLocalMonitor({
                localMonitor: share
            }).then(function() {
                console.log("SelectLocalMonitor Success");
            }).catch(function() {
                console.error("SelectLocalMonitor Failed");
            });
        });
    });

    // A window was selected from the "Window Share" drop-down list.
    // Note: in Transcoding WebRTC mode, this is only called for the "None" option (to stop the share) since
    //       the share is selected in the onAdded callback of the LocalWindowShareEventListener.
    $("#windowShares").change(function() {
        console.log("*** Window shares change called");

        // Find the share selected from the drop-down list
        $("#windowShares option:selected").each(function() {
            share = windowShares[$(this).val()];

            // Select the local window share
            vidyoConnector.SelectLocalWindowShare({
                localWindowShare: share
            }).then(function() {
                console.log("SelectLocalWindowShare Success");
            }).catch(function() {
                console.error("SelectLocalWindowShare Failed");
            });
        });
    });
}

function getParticipantName(participant, cb) {
    if (!participant) {
        cb("Undefined");
        return;
    }

    if (participant.name) {
        cb(participant.name);
        return;
    }

    participant.GetName().then(function(name) {
        cb(name);
    }).catch(function() {
        cb("GetNameFailed");
    });
}

function handleParticipantChange(vidyoConnector) {
    vidyoConnector.RegisterParticipantEventListener({
        onJoined: function(participant) {
            getParticipantName(participant, function(name) {
                $("#participantStatus").html("" + name + " Joined");
            });
        },
        onLeft: function(participant) {
            getParticipantName(participant, function(name) {
                $("#participantStatus").html("" + name + " Left");
            });
        },
        onDynamicChanged: function(participants) {
            // Order of participants changed
        },
        onLoudestChanged: function(participant, audioOnly) {
            getParticipantName(participant, function(name) {
                $("#participantStatus").html("" + name + " Speaking");
            });
        }
    }).then(function() {
        console.log("RegisterParticipantEventListener Success");
    }).catch(function() {
        console.err("RegisterParticipantEventListener Failed");
    });
}

// Attempt to connect to the conference
// We will also handle connection failures
// and network or server-initiated disconnects.
function connectToConference(vidyoConnector, returnURL) {
    // Abort the Connect call if roomKey is invalid. It cannot contain empty spaces or "@".
    if ( $("#roomKey").val().indexOf(" ") != -1 || $("#roomKey").val().indexOf("@") != -1) {
        console.error("Connect call aborted due to invalid Room Key");
        connectorDisconnected(vidyoConnector, rendererSlots, remoteCameras, "Disconnected", "", returnURL);
        $("#error").html("<h3>Failed due to invalid Room Key" + "</h3>");
        return;
    }

    // Clear messages
    $("#error").html("");
    $("#message").html("<h3 class='blink'>CONNECTING...</h3>");

    vidyoConnector.ConnectToRoomAsGuest({
        // Take input from options form
        host: $("#portal").val(),
        displayName: $("#displayName").val(),
        roomKey: $("#roomKey").val(),
        roomPin: $("#roomPin").val(),

        // Define handlers for connection events.
        onSuccess: function() {
            // Connected
            console.log("vidyoConnector.Connect : onSuccess callback received");
            $("#connectionStatus").html("Connected");
            $("#options").addClass("hidden");
            $("#optionsVisibilityButton").addClass("showOptions").removeClass("hideOptions");
            $("#renderer").addClass("rendererFullScreen").removeClass("rendererWithOptions");
            ShowRenderer(vidyoConnector);
            $("#message").html("");
        },
        onFailure: function(reason) {
            // Failed
            console.error("vidyoConnector.Connect : onFailure callback received");
            connectorDisconnected(vidyoConnector, "Failed", "", returnURL);
            $("#error").html("<h3>Call Failed: " + reason + "</h3>");
        },
        onDisconnected: function(reason) {
            // Disconnected
            console.log("vidyoConnector.Connect : onDisconnected callback received");
            connectorDisconnected(vidyoConnector, "Disconnected", "Call Disconnected: " + reason, returnURL);

            $("#options").removeClass("hidden");
            $("#optionsVisibilityButton").addClass("hideOptions").removeClass("showOptions");
            $("#renderer").removeClass("rendererFullScreen").addClass("rendererWithOptions");
            ShowRenderer(vidyoConnector);
        }
    }).then(function(status) {
        if (status) {
            console.log("Connect Success");
        } else {
            console.error("Connect Failed");
            connectorDisconnected(vidyoConnector, "Failed", "", returnURL);
            $("#error").html("<h3>Call Failed" + "</h3>");
        }
    }).catch(function() {
        console.error("Connect Failed");
        connectorDisconnected(vidyoConnector, "Failed", "", returnURL);
        $("#error").html("<h3>Call Failed" + "</h3>");
    });
}

// Connector either fails to connect or a disconnect completed, update UI elements
function connectorDisconnected(vidyoConnector, connectionStatus, message, returnURL) {
    // If "returnURL" argument was passed in the URL, then redirect to that URL after disconnecting.
    if (!returnURL) {
        $("#connectionStatus").html(connectionStatus);
        $("#message").html(message);
        $("#participantStatus").html("");
        $("#joinLeaveButton").removeClass("callEnd").addClass("callStart");
        $('#joinLeaveButton').prop('title', 'Join Conference');
    } else {
        // Disable the connector to release devices and then destruct it.
        vidyoConnector.Disable();
        vidyoConnector.Destruct();

        // Redirect to the returnURL.
        window.location.href = returnURL;
    }
}


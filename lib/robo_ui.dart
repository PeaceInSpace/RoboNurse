import 'dart:async';
import 'package:control_pad/models/gestures.dart';
import 'package:control_pad/models/pad_button_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:provider/provider.dart';
import './mqtt/mqtt_manager.dart';
import './mqtt/state/mqtt_state.dart';
import 'package:control_pad/control_pad.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'dart:convert';
import 'package:connectivity/connectivity.dart';

import 'custom_widgets/temperature_indicator.dart';

class RoboUI extends StatefulWidget {
  RoboUI({Key key}) : super(key: key);
  @override
  RoboUIState createState() => RoboUIState();
}

class RoboUIState extends State<RoboUI> with TickerProviderStateMixin {
  MQTTAppState currentAppState;
  MQTTManager manager;
  bool controllerType = true;
  bool cameraSwitch = true;
  bool createConnection = false;
  bool switchMicrophone = true;
  String serverConnection = "Link";
  String roboDisplayCandidate = "";
  String robotConnection = "Connect";
  bool robotFlashLight = false;
  bool isServerConnected = false;
  bool isConnectedToRobotDisplay = false;
  //webRTC
  bool _offer = false;
  RTCPeerConnection _peerConnection;
  MediaStream _localStream;
  final _localRenderer = new RTCVideoRenderer();
  final _remoteRenderer = new RTCVideoRenderer();
  List<String> candidates = [];
  Connectivity connectivity;
  StreamSubscription<ConnectivityResult> subscription;
  bool networkAvailable = false;
  double sliderValue = 1;
  Color brakeColor = Colors.tealAccent;
  AnimationController progressController;
  Animation<double> tempAnimation;
  AnimationController colorAnimationController;
  Animation _colorTween;
  double currentTemperature = 10.0;
  bool temperatureUnitIsCelcius = true;
  String temperatureUnit = '°C';
  // bool isScrolling = true;
  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    subscription.cancel();
    super.dispose();
  }

  @override
  void initState() {
    initRenderers();
    // _createPeerConnection().then((pc) {
    //   _peerConnection = pc;
    // });
    super.initState();
    dashboardInit(currentTemperature);
    connectivity = new Connectivity();
    subscription =
        connectivity.onConnectivityChanged.listen((ConnectivityResult status) {
      if (status == ConnectivityResult.wifi ||
          status == ConnectivityResult.mobile) {
        setState(() {
          networkAvailable = true;
          serverConnection = "Link";
          isServerConnected = false;
        });
      } else {
        setState(() {
          networkAvailable = false;
        });
      }
    });
  }

//--------------------------- WebRTC Code ------------------------------------------------
  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _createPeerConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
        {"url": "stun:stun1.l.google.com:19302"},
        {"url": "stun:stun2.l.google.com:19302"},
        {"url": "stun:stun3.l.google.com:19302"},
        {"url": "stun:stun4.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };
    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
        await createPeerConnection(configuration, offerSdpConstraints);
    pc.addStream(_localStream);
    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        candidates.add(json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMlineIndex
        }));
      }
    };
    pc.onIceConnectionState = (e) {
      print(e);
    };
    pc.onAddStream = (stream) {
      print("addStream: " + stream.id);
      _remoteRenderer.srcObject = stream;
    };
    return pc;
  }

  _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      }
    };

    MediaStream stream = await navigator.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = stream;
    _localRenderer.mirror = true;
    return stream;
  }

  _createOffer() async {
    if (candidates.length > 0) candidates.clear();
    print(
        "------------------step1  create an offer ---------------------------------------");
    RTCSessionDescription description =
        await _peerConnection.createOffer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp);
    _offer = true;
    _peerConnection.setLocalDescription(description);
    // jsonEncode(session);
    String offerToPublish = json.encode(session);
    return offerToPublish;
  }

  void _createAnswer() async {
    RTCSessionDescription description =
        await _peerConnection.createAnswer({'offerToReceiveVideo': 1});
    var session = parse(description.sdp);
    print(json.encode(session));

    _peerConnection.setLocalDescription(description);
  }

  void setRoboDisplayRemoteDescription(String remoteSession) async {
    print(
        "------------------step4  set Answer as Remote Description ---------------------------------------");
    dynamic session = await jsonDecode(remoteSession);
    String sdp = write(session, null);
    RTCSessionDescription description =
        new RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    print(description.toMap());
    await _peerConnection.setRemoteDescription(description);
    // _publishMessage("offer/description", "answer_is_set");
    if (candidates.length > 0)
      _publishMessage("offer/candidate", json.encode(candidates));
  }

  void setRoboDisplayCandidate(String roboDisplayCandidate) async {
    print(
        "------------------step5  send a candidate ---------------------------------------");
    var allCandidates = json.decode(roboDisplayCandidate);
    allCandidates.forEach((sessionCandidate) async {
      dynamic session = await jsonDecode(sessionCandidate);
      print(session['candidate']);
      dynamic candidate = new RTCIceCandidate(
          session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
      await _peerConnection.addCandidate(candidate);
    });
  }

  void turnOffCamera() {
    _peerConnection.close();
    _localStream.dispose();
    // _localRenderer.dispose();
    // _remoteRenderer.dispose();
    _publishMessage("offer/disconnected", "disconnected");
  }

  void turnOnCamera() {
    _publishMessage("offer/connected", "connected");
    _createPeerConnection().then((pc) {
      _peerConnection = pc;
      _createOffer().then((message) {
        print("this is an offer ---> $message");
        _publishMessage("offer/roboNurse", message);
      });
    });
  }

  void switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  void switchMic(bool value) {
    if (_localStream != null) {
      value
          ? _localStream.getAudioTracks()[0].enabled = true
          : _localStream.getAudioTracks()[0].enabled = false;
      // if (value) {
      //   _localStream.getAudioTracks()[0].enabled = true;
      // } else {
      //   _localStream.getAudioTracks()[0].enabled = false;
      // }
    }
  }

  void robotFlash(bool value) {
    _publishMessage("robot_flash_light", value.toString());
  }
//--------------------------- WebRTC Code ------------------------------------------------

  dashboardInit(double temp) {
    var temperature;
    temperatureUnitIsCelcius
        ? temperature = temp
        : temperature = (temp * (9 / 5)) + 32;
    progressController =
        AnimationController(vsync: this, duration: Duration(seconds: 4)); //5s

    tempAnimation =
        Tween<double>(begin: 0, end: temperature).animate(progressController)
          ..addListener(() {
            setState(() {
              currentTemperature = temp;
            });
          });

    progressController.forward();

    colorAnimationController =
        AnimationController(vsync: this, duration: Duration(seconds: 4));
    _colorTween = ColorTween(begin: Colors.tealAccent, end: Colors.red)
        .animate(colorAnimationController);
    colorAnimationController.animateTo(temp / 100);
  }

  @override
  Widget build(BuildContext context) {
    final MQTTAppState appState = Provider.of<MQTTAppState>(context);
    currentAppState = appState;
    return Scaffold(
        resizeToAvoidBottomPadding: false,
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) {
            if (networkAvailable)
              return tabController(context);
            else
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.signal_wifi_off,
                      size: 100.0,
                      color: Colors.tealAccent,
                    ),
                    Text(
                      "Seems like you are offline",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                          fontFamily: "Raleway",
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
          },
        ));
  }

  Widget tabController(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: 1,
      child: Scaffold(
          body: SafeArea(
              child: Column(children: <Widget>[
        Container(
          color: Colors.black,
          height: (MediaQuery.of(context).size.height / 2.2) + 100,
          child: Stack(children: <Widget>[
            Positioned(
                left: 0.0,
                right: 0.0,
                top: 0.0,
                bottom: 0.0,
                child: Container(
                  margin: EdgeInsets.fromLTRB(0, 0, 0, 0),
                  // width: double.infinity,
                  // height: double.infinity,
                  child: createConnection
                      ? RTCVideoView(_remoteRenderer)
                      : Container(
                          color: Colors.black,
                        ),
                  decoration: BoxDecoration(color: Colors.black54),
                )),
            Positioned(
              left: 5.0,
              top: 20.0,
              child: Container(
                width: 90.0,
                height: 120.0,
                child: createConnection
                    ? RTCVideoView(_localRenderer)
                    : Container(
                        color: Colors.transparent,
                      ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
            ),
          ]),
        ),
        PreferredSize(
          preferredSize: Size.fromHeight(50.0),
          child: Container(
            child: TabBar(
              labelColor: Colors.tealAccent,
              tabs: [
                Tab(
                  text: "Controller",
                ),
                Tab(
                  text: 'Robot Display',
                ),
                Tab(
                  text: 'Connection',
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            // physics:
            //     isScrolling ? ScrollPhysics(): NeverScrollableScrollPhysics(),
            children: [
              Container(
                  color: Colors.black,
                  child: AbsorbPointer(
                    absorbing: !isServerConnected,
                    child: Row(
                      // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Spacer(
                          flex: 1,
                        ),
                        SafeArea(child: controllerMode(controllerType)),
                        Spacer(
                          flex: 1,
                        ),
                        RaisedButton(
                          child: Text(
                            "Brake",
                            style: TextStyle(
                                color: Colors.black,
                                fontFamily: "Raleway",
                                fontWeight: FontWeight.bold),
                          ),
                          color: isServerConnected
                              ? Colors.tealAccent
                              : Colors.teal[100],
                          onPressed: () {
                            setState(() {
                              _publishMessage("brakes", "S");
                            });
                          },
                        ),
                        Spacer(
                          flex: 1,
                        ),
                      ],
                    ),
                  )),
              Container(
                color: Colors.black,
                child: AbsorbPointer(
                  absorbing: !isServerConnected,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 15.0,
                        left: 20.0,
                        child: AbsorbPointer(
                          absorbing: !isConnectedToRobotDisplay,
                          child: Container(
                            child: Row(
                              children: [
                                Icon(Icons.camera_rear),
                                Switch(
                                  activeColor: (isServerConnected &&
                                          isConnectedToRobotDisplay)
                                      ? Colors.tealAccent
                                      : Colors.teal[100],
                                  value: cameraSwitch,
                                  onChanged: (value) {
                                    switchCamera();
                                    setState(() {
                                      cameraSwitch = value;
                                    });
                                  },
                                ),
                                Icon(Icons.camera_front),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 80.0,
                        left: 20.0,
                        child: AbsorbPointer(
                          absorbing: !isConnectedToRobotDisplay,
                          child: Container(
                            child: Row(
                              children: [
                                Icon(Icons.mic_off),
                                Switch(
                                  activeColor: (isServerConnected &&
                                          isConnectedToRobotDisplay)
                                      ? Colors.tealAccent
                                      : Colors.teal[100],
                                  value: switchMicrophone,
                                  onChanged: (value) {
                                    switchMic(value);
                                    setState(() {
                                      switchMicrophone = value;
                                    });
                                  },
                                ),
                                Icon(Icons.mic),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 145.0,
                        left: 20.0,
                        child: Container(
                          child: Row(
                            children: [
                              Icon(Icons.flash_off),
                              Switch(
                                activeColor: Colors.tealAccent,
                                value: robotFlashLight,
                                onChanged: (value) {
                                  robotFlash(value);
                                  setState(() {
                                    robotFlashLight = value;
                                  });
                                },
                              ),
                              Icon(Icons.flash_on),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 5.0,
                        right: 20.0,
                        child: StatefulBuilder(
                          builder:
                              (BuildContext context, StateSetter stateSetter) {
                            return CustomPaint(
                              foregroundPainter:
                                  // CircleProgress(tempAnimation.value, true),
                                  CircleProgress(
                                      tempAnimation?.value ?? 1.0,
                                      temperatureUnitIsCelcius,
                                      _colorTween?.value),
                              child: GestureDetector(
                                onTap: () => _publishMessage(
                                    "get_temperature", "body_temperature"),
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Text(
                                          '${tempAnimation?.value?.toInt() ?? 0}',
                                          style: TextStyle(
                                              color: _colorTween?.value,
                                              fontSize: 50,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          '$temperatureUnit',
                                          style: TextStyle(
                                              color: _colorTween?.value,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      //Add temperature reading
                      // Spacer(
                      //   flex: 1,
                      // ),
                    ],
                  ),
                ),
              ),
              Container(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      Positioned(
                        right: 5.0,
                        child: IconButton(
                          color: Colors.tealAccent,
                          icon: Icon(Icons.settings),
                          onPressed: settingsWidget,
                        ),
                      ),
                      Center(
                        heightFactor: 3.79,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          // crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                isServerConnected
                                    ? Icons.cloud_done
                                    : Icons.cloud,
                                size: 76.0,
                                color: Colors.tealAccent,
                              ),
                              onPressed: () {
                                if (currentAppState.getAppConnectionState ==
                                    MQTTAppConnectionState.disconnected) {
                                  _configureAndConnect();
                                  Scaffold.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                      "Connected",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: "Raleway",
                                          fontWeight: FontWeight.bold),
                                    ),
                                    backgroundColor: Colors.tealAccent,
                                  ));
                                  setState(() {
                                    isServerConnected = true;
                                    serverConnection = "Unlink";
                                  });
                                } else if (currentAppState
                                        .getAppConnectionState ==
                                    MQTTAppConnectionState.connected) {
                                  _disconnect();
                                  Scaffold.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                      "Disconnected",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: "Raleway",
                                          fontWeight: FontWeight.bold),
                                    ),
                                    backgroundColor: Colors.tealAccent,
                                  ));
                                  setState(() {
                                    isServerConnected = false;
                                    serverConnection = "Link";
                                  });
                                }
                              },
                              // padding: EdgeInsets.all(15.0),
                            ),
                            SizedBox(width: 80.0),
                            IconButton(
                              icon: Icon(
                                isConnectedToRobotDisplay
                                    ? Icons.videocam_off
                                    : Icons.videocam,
                                size: 76.0,
                              ),
                              color: isServerConnected
                                  ? Colors.tealAccent
                                  : Colors.teal[100],
                              onPressed: () {
                                createConnection
                                    ? turnOffCamera()
                                    : turnOnCamera();
                                setState(() {
                                  isConnectedToRobotDisplay
                                      ? isConnectedToRobotDisplay = false
                                      : isConnectedToRobotDisplay = true;
                                  createConnection
                                      ? robotConnection = "Connect"
                                      : robotConnection = "Disconnect";
                                  createConnection
                                      ? createConnection = false
                                      : createConnection = true;
                                });
                              },
                            ),
                            SizedBox(
                              width: 45.0,
                            )
                          ],
                        ),
                      ),
                    ],
                  )),
            ],
          ),
        ),
      ]))),
    );
  }

  Widget controllerMode(bool type) {
    if (type) {
      return PadButtonsView(
          buttons: [
            PadButtonItem(
                index: 0,
                buttonIcon: Icon(Icons.keyboard_arrow_right),
                backgroundColor: Colors.black),
            PadButtonItem(
                index: 1,
                buttonIcon: Icon(Icons.keyboard_arrow_down),
                backgroundColor: Colors.black),
            PadButtonItem(
                index: 2,
                buttonIcon: Icon(Icons.keyboard_arrow_left),
                backgroundColor: Colors.black),
            PadButtonItem(
                index: 3,
                buttonIcon: Icon(Icons.keyboard_arrow_up),
                backgroundColor: Colors.black)
          ],
          backgroundPadButtonsColor:
              isServerConnected ? Colors.tealAccent : Colors.teal[100],
          padButtonPressedCallback: robotDirection);
    } else {
      return JoystickView(
        backgroundColor:
            isServerConnected ? Colors.tealAccent : Colors.teal[100],
        iconsColor: Colors.black,
        innerCircleColor: Colors.black,
        showArrows: false,
        onDirectionChanged: robotJoyStickDirection,
      );
    }
  }

  void settingsWidget() {
    showModalBottomSheet(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        // side: BorderSide(color: Colors.tealAccent),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      context: context,
      isScrollControlled: true, // set this to true
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter stateSetter) {
            return Container(
              height: 180.0,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.0),
                  topRight: Radius.circular(20.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.tealAccent,
                    offset: Offset(0.0, -1.0), //(x,y)
                    blurRadius: 2.0,
                  ),
                ],
              ),
              child:Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20.0, horizontal: 20.0),
                    child: Column(
                      // controller: controller,
                      children: [
                        ListTile(
                          leading: Text("Temperature unit",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20.0,
                                  fontFamily: "Raleway",
                                  fontWeight: FontWeight.bold)),
                          trailing: Switch(
                            activeColor: Colors.tealAccent,
                            value: temperatureUnitIsCelcius,
                            onChanged: (value) {
                              stateSetter(() {
                                temperatureUnitIsCelcius = value;
                                value
                                    ? temperatureUnit = '°C'
                                    : temperatureUnit = '°F';
                                dashboardInit(currentTemperature);
                              });
                            },
                          ),
                        ),
                        ListTile(
                          leading: Text("App Info",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20.0,
                                  fontFamily: "Raleway",
                                  fontWeight: FontWeight.bold)),
                          trailing: IconButton(
                            icon: Icon(Icons.info_outline),
                            color: Colors.white,
                            onPressed: showAppinfo,
                          ),
                        ),
                      ],
                    ),
                  ),
              );
          },
        );
      },
    );
  }

  void showAppinfo() {
    showAboutDialog(
        context: context,
        applicationIcon: Container(
          width: 40.0,
          height: 41.0,
          child: Image.asset('assets/icon/icon.png'),
        ),
        applicationVersion: "1.0.1",
        applicationLegalese:
            "Developer, Abhishek Gelot \n abhigelot123@gmail.com \n \n Copr \u00A9 Abhishek Gelot.");
  }

// ------------------------------------- MQTT server connection ----------------------------------------
  void _configureAndConnect() {
    manager = MQTTManager(state: currentAppState);
    manager.initializeMQTTClient();
    manager.connect();
  }

  void _disconnect() {
    manager.disconnect();
  }

  void _publishMessage(String topic, String message) {
    manager.publish(topic, message);
  }

  void robotDirection(int index, Gestures gestures) {
    const String topic = "robot_direction";
    switch (index) {
      case 0:
        {
          _publishMessage(topic, "R");
        }
        break;
      case 1:
        {
          _publishMessage(topic, "B");
        }
        break;
      case 2:
        {
          _publishMessage(topic, "L");
        }
        break;
      case 3:
        {
          _publishMessage(topic, "F");
        }
        break;
      default:
        break;
    }
  }

// ------------------------------------- MQTT server connection ----------------------------------------

  void robotJoyStickDirection(double angle, double y) {
    const String topic = "robot_direction";
    if (315 <= angle || angle <= 45)
      _publishMessage(topic, "F");
    else if (45 <= angle || angle <= 135)
      _publishMessage(topic, "R");
    else if (135 <= angle || angle <= 225)
      _publishMessage(topic, "B");
    else if (225 <= angle || angle <= 315) _publishMessage(topic, "L");
  }
}

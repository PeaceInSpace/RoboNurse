import 'package:flutter/cupertino.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../mqtt/state/mqtt_state.dart';
import '../main.dart';

class MQTTManager {
  // Private instance of client
  final MQTTAppState _currentState;
  MqttServerClient _client;

  // Constructor
  MQTTManager({
    @required MQTTAppState state,
  }) : _currentState = state;

  void initializeMQTTClient() {
    _client = MqttServerClient("hairdresser.cloudmqtt.com", "abhishek");
    // _client = MqttServerClient("broker.hivemq.com","abhishek");
    _client.port = 16642;
    // _client.port = 1883;
    // _client.clientIdentifier = "";
    _client.keepAlivePeriod = 3600;
    _client.onDisconnected = onDisconnected;
    // _client.autoReconnect = true;
    // _client.secure = false;
    _client.logging(on: false);

    /// Add the successful connection callback
    _client.onConnected = onConnected;
    _client.onSubscribed = onSubscribed;

    final MqttConnectMessage connMess = MqttConnectMessage()
        // .authenticateAs("ngtyutmq", "mItz0RMt1UtC")
        // .startClean() // Non persistent session for testing
        .withClientIdentifier("abhishek")
        .withWillQos(MqttQos.atLeastOnce);

    print('EXAMPLE::Mosquitto client connecting....');
    _client.connectionMessage = connMess;
  }

  // Connect to the host
  void connect() async {
    assert(_client != null);
    try {
      print('EXAMPLE::Mosquitto start client connecting....');
      _currentState.setAppConnectionState(MQTTAppConnectionState.connecting);
      await _client.connect("ngtyutmq", "mItz0RMt1UtC");
    } on Exception catch (e) {
      print('EXAMPLE::client exception - $e');
      disconnect();
    }
  }

  void disconnect() {
    print('Disconnected');
    _client.disconnect();
  }

  void publish(String topic, String message) {
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload);
  }

  /// The subscribed callback
  void onSubscribed(String topic) {
    print('EXAMPLE::Subscription confirmed for topic $topic');
  }

  /// The unsolicited disconnect callback
  void onDisconnected() {
    print('EXAMPLE::OnDisconnected client callback - Client disconnection');
    if (_client.connectionStatus.returnCode ==
        MqttConnectReturnCode.noneSpecified) {
      print('EXAMPLE::OnDisconnected callback is solicited, this is correct');
    }
    _currentState.setAppConnectionState(MQTTAppConnectionState.disconnected);
  }

  /// The successful connect callback
  void onConnected() {
    _currentState.setAppConnectionState(MQTTAppConnectionState.connected);
    print('EXAMPLE::Mosquitto client connected....');
    _client.subscribe('answer/roboDisplay', MqttQos.atLeastOnce);
    _client.subscribe('answer/candidate', MqttQos.atLeastOnce);
    _client.subscribe("set_temperature", MqttQos.atLeastOnce);
    _client.updates.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload;
      final String pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      // _currentState.setReceivedText(pt);
      print(
          'EXAMPLE::Change notification:: topic is ${c[0].topic}, payload is <-- $pt -->');
      if (c[0].topic.toString() == "answer/roboDisplay") {
        key.currentState.setRoboDisplayRemoteDescription(pt);
      } else if (c[0].topic.toString() == "answer/candidate") {
        // key.currentState.setRoboDisplayCandidate(pt);
      } else if (c[0].topic.toString() == "set_temperature"){
          key.currentState.dashboardInit(double.parse(pt));
      }
    });
    print(
        'EXAMPLE::OnConnected client callback - Client connection was sucessful');
  }
}

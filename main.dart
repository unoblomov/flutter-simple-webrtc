
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(MaterialApp(home: SimpleWebRTC()));
}

class SimpleWebRTC extends StatefulWidget {
  @override
  State<SimpleWebRTC> createState() => _SimpleWebRTCState();
}

class _SimpleWebRTCState extends State<SimpleWebRTC> {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  TextEditingController offerController = TextEditingController();
  TextEditingController answerController = TextEditingController();
  TextEditingController candidatesController = TextEditingController();

  String status = "Bağlı değil";
  String remoteMessage = "";

  final Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // TURN server eklemek istersen buraya ekle
    ],
  };

  @override
  void dispose() {
    _peerConnection?.close();
    super.dispose();
  }

  Future<void> initPeerConnection({required bool isCaller}) async {
    _peerConnection = await createPeerConnection(iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        final jsonCandidate = jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
        // Yeni ICE adayını alt alta ekle
        candidatesController.text += jsonCandidate + "\n";
      }
    };

    if (isCaller) {
      _dataChannel = await _peerConnection!.createDataChannel('data', RTCDataChannelInit());

      _dataChannel!.onMessage = (msg) {
        setState(() {
          remoteMessage = "Karşıdan: ${msg.text}";
        });
      };

      _dataChannel!.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          setState(() {
            status = "Bağlandı (Caller)";
          });
        }
      };

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      offerController.text = jsonEncode({'sdp': offer.sdp, 'type': offer.type});
      setState(() {
        status = "Offer oluşturuldu, karşı tarafa gönder";
      });
    } else {
      _peerConnection!.onDataChannel = (channel) {
        _dataChannel = channel;

        _dataChannel!.onMessage = (msg) {
          setState(() {
            remoteMessage = "Karşıdan: ${msg.text}";
          });
        };

        _dataChannel!.onDataChannelState = (state) {
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            setState(() {
              status = "Bağlandı (Callee)";
            });
          }
        };
      };

      setState(() {
        status = "Callee, offer bekliyor";
      });
    }
  }

  Future<void> setRemoteDescriptionFromText(String jsonText) async {
    try {
      final json = jsonDecode(jsonText);
      final sdp = json['sdp'];
      final type = json['type'];
      final description = RTCSessionDescription(sdp, type);
      await _peerConnection!.setRemoteDescription(description);
    } catch (e) {
      print("Hata setRemoteDescriptionFromText: $e");
    }
  }

  Future<void> addIceCandidatesFromText(String candidatesText) async {
    final lines = candidatesText.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line);
        final candidate = RTCIceCandidate(json['candidate'], json['sdpMid'], json['sdpMLineIndex']);
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        print("ICE candidate eklerken hata: $e");
      }
    }
  }

  void sendMessage(String text) {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(text));
      setState(() {
        remoteMessage = "Sen: $text";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Minimal WebRTC")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("1) Caller mı? Oluşturmak için 'Caller Ol' butonuna bas"),
            ElevatedButton(
              onPressed: () async {
                await initPeerConnection(isCaller: true);
              },
              child: Text("Caller Ol"),
            ),
            SizedBox(height: 10),

            Text("2) Offer (Caller'dan alıp buraya yapıştır):"),
            TextField(controller: offerController, maxLines: 5, decoration: InputDecoration(border: OutlineInputBorder())),
            ElevatedButton(
              onPressed: () async {
                if (_peerConnection == null) {
                  await initPeerConnection(isCaller: false);
                }
                await setRemoteDescriptionFromText(offerController.text);
                final answer = await _peerConnection!.createAnswer();
                await _peerConnection!.setLocalDescription(answer);
                answerController.text = jsonEncode({'sdp': answer.sdp, 'type': answer.type});
                setState(() {
                  status = "Answer oluşturuldu ve set edildi (Callee)";
                });
              },
              child: Text("Offer'ı al, Answer oluştur"),
            ),
            SizedBox(height: 10),

            Text("3) Answer (Callee'den al, buraya yapıştır ve set et)"),
            TextField(controller: answerController, maxLines: 5, decoration: InputDecoration(border: OutlineInputBorder())),
            ElevatedButton(
              onPressed: () async {
                await setRemoteDescriptionFromText(answerController.text);
                setState(() {
                  status = "Answer set edildi (Caller)";
                });
              },
              child: Text("Answer'ı set et"),
            ),
            SizedBox(height: 10),

            Text("4) ICE Candidate'ları (Her iki taraftan da çıkanları buraya yapıştır, 'ICE Ekle'ye bas)"),
            TextField(controller: candidatesController, maxLines: 8, decoration: InputDecoration(border: OutlineInputBorder())),
            ElevatedButton(
              onPressed: () async {
                await addIceCandidatesFromText(candidatesController.text);
              },
              child: Text("ICE Ekle"),
            ),
            SizedBox(height: 20),

            Text("Durum: $status"),
            SizedBox(height: 20),

            Text("Mesaj Gönder (DataChannel açıksa):"),
            Row(
              children: [
                Expanded(child: TextField(onSubmitted: sendMessage, decoration: InputDecoration(hintText: "Mesaj yazıp Enter'a bas"))),
              ],
            ),
            SizedBox(height: 20),

            Text(remoteMessage),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  var responseUuid;

  Future<String> sendPhoneNumber(String phoneNumber) async {
    var uri = Uri.parse('https://direct.i-dgtl.ru/api/v1/verifier/send');
    var headers = {
      'Authorization': 'Basic OTQ3NDpmNmEySEhBYUNiVkNPT0V3djNhYnhl',
      'Accept': 'application/json',
      'Content-type': 'application/json'
    };
    var body = jsonEncode({
      "channelType": "SMS",
      "destination": phoneNumber,
      "gatewayId": "TIrqKG"
    });
    var response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      responseUuid = json.decode(response.body)['uuid'];
      return responseUuid;
    } else {
      throw Exception('Ошибка отправки СМС');
    }
  }

  Future<bool> verifyCode(String uuid, String code) async {
    var uri = Uri.parse('https://direct.i-dgtl.ru/api/v1/verifier/check');
    var headers = {
      'Authorization': 'Basic OTQ3NDpmNmEySEhBYUNiVkNPT0V3djNhYnhl',
      'Accept': 'application/json',
      'Content-type': 'application/json'
    };
    var body = jsonEncode({"uuid": uuid, "code": code});
    var response = await http.post(uri, headers: headers, body: body);
    var responseStatus = json.decode(response.body)['status'];
    return responseStatus == 'CONFIRMED';
  }

  Future<void> registerUser(
      String phoneNumber, String uuid, String code) async {
    final isVerified = await verifyCode(uuid, code);
    if (isVerified) {
      final userData = {
        'phonenumber': phoneNumber,
        'id': uuid,
        'otp': code,
        'name': '',
      };
      await _saveOrUpdateUser(userData);
    } else {
      throw Exception('Неверный код СМС');
    }
  }

  Future<void> _saveOrUpdateUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final existingPhoneNumber = prefs.getString('user_phonenumber');

    if (existingPhoneNumber == userData['phonenumber']) {
      final existingUserId = prefs.getString('user_id');
      await _firestore.collection('usersSMS').doc(existingUserId).update({
        'otp': userData['otp'],
      });
    } else {
      await _firestore.collection('usersSMS').doc(userData['id']).set(userData);
    }

    await _saveUserToSharedPreferences(userData);
  }

  Future<void> _saveUserToSharedPreferences(
      Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userData['id']);
    await prefs.setString('user_phonenumber', userData['phonenumber']);
    await prefs.setString('user_otp', userData['otp']);
    await prefs.setString('user_name', userData['name']);
  }

  Future<bool> isUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final phoneNumber = prefs.getString('user_phonenumber');
    final otp = prefs.getString('user_otp');

    if (userId == null || phoneNumber == null || otp == null) {
      return false;
    }

    final querySnapshot = await _firestore
        .collection('usersSMS')
        .where('id', isEqualTo: userId)
        .where('phonenumber', isEqualTo: phoneNumber)
        .where('otp', isEqualTo: otp)
        .get();

    return querySnapshot.docs.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      return null;
    }

    final docSnapshot = await _firestore.collection('usersSMS').doc(userId).get();
    return docSnapshot.data();
  }

  Future<void> updateUserData(Map<String, dynamic> updatedData) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      throw Exception('Нет пользователя');
    }

    await _firestore.collection('usersSMS').doc(userId).update(updatedData);
    await _saveUserToSharedPreferences(updatedData);
  }

  Future<void> deleteUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      throw Exception('Нет пользователя');
    }

    await _firestore.collection('usersSMS').doc(userId).delete();
    await prefs.clear();
    exit(0);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final phoneNumber = prefs.getString('user_phonenumber');
    final userId = prefs.getString('user_id');

    if (phoneNumber != null && userId != null) {
      await prefs.setString('user_otp', '');
    }
    exit(0);
  }
}

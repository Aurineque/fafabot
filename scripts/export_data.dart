import 'dart:io';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/firebase_options.dart'; // Importe suas opções do Firebase

Future<void> main() async {
  // Inicializa o Firebase para o script
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print("Conectado ao Firebase. Buscando dados da coleção 'sessoes_de_conversa'...");

  final firestore = FirebaseFirestore.instance;
  final collectionRef = firestore.collection('sessoes_de_conversa');

  try {
    final querySnapshot = await collectionRef.get();
    final List<Map<String, dynamic>> todasAsSessoes = [];

    for (var docSnapshot in querySnapshot.docs) {
      todasAsSessoes.add(docSnapshot.data());
    }

    if (todasAsSessoes.isNotEmpty) {
      // Codifica a lista inteira para uma string JSON formatada
      final jsonString = JsonEncoder.withIndent('  ').convert(todasAsSessoes);
      
      // Salva a string em um arquivo na raiz do projeto
      final file = File('conversas_exportadas.json');
      await file.writeAsString(jsonString);

      print("\nSucesso! ${todasAsSessoes.length} sessões de conversa foram salvas em 'conversas_exportadas.json'");
    } else {
      print("Nenhuma conversa encontrada na coleção.");
    }
  } catch (e) {
    print("\nERRO ao buscar dados: $e");
  }
}
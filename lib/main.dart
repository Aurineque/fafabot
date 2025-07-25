import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '/constants/prompts.dart';
import 'dart:convert';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fafabot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(

        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {  
  final TextEditingController _userInput = TextEditingController();

  //late final String apiKey;

  final List<Message> _messages = [];

  ChatPhase _currentPhase = ChatPhase.explorar;

  late GenerativeModel modeloPrincipal;
  late GenerativeModel modeloAnalisador;

  @override
  void initState() {
    super.initState();
    modeloPrincipal = GenerativeModel(
      model: 'gemini-1.5-pro-latest', // para conversa
      apiKey: dotenv.env['API_KEY_principal']!,
    );
    modeloAnalisador = GenerativeModel(
      model: 'gemini-1.5-flash-latest', // para análise/JSON
      apiKey: dotenv.env['API_KEY_secundario']!,
    );
  }

Future<Map<String, dynamic>> analisarDialogo(String dialogoHistorico, ChatPhase faseAtual) async {
  String? promptAnalisador;

  // Usa um switch para selecionar o prompt correto.
  switch (faseAtual) {
    case ChatPhase.explorar:
      promptAnalisador = AppPrompts.analisadorPromptExplorar;
      break;
    case ChatPhase.rotular:
      promptAnalisador = AppPrompts.analisadorPromptRotular;
      break;
    case ChatPhase.busca:
    promptAnalisador = AppPrompts.analisadorPromptBusca;
    break;
  case ChatPhase.gravacao:
    promptAnalisador = AppPrompts.analisadorPromptGravacao;
    break;
  case ChatPhase.compartilhar:
    promptAnalisador = AppPrompts.analisadorPromptCompartilhar;
    break;
  }
  
  final promptCompleto = promptAnalisador + dialogoHistorico;
  String? respostaOriginal; // Variável para guardar a resposta original

  try {
    final response = await modeloAnalisador.generateContent([
      Content.text(promptCompleto),
    ]);
    
    respostaOriginal = response.text; // Guarda a resposta para depuração

    if (respostaOriginal != null) {
      // =======================================================
      // LÓGICA DE EXTRAÇÃO DE JSON
      // =======================================================
      
      // 1. Encontra o primeiro '{' na resposta
      final int startIndex = respostaOriginal.indexOf('{');
      
      // 2. Encontra o último '}' na resposta
      final int endIndex = respostaOriginal.lastIndexOf('}');

      // 3. Se ambos foram encontrados, extrai a substring entre eles
      if (startIndex != -1 && endIndex != -1) {
        final String jsonString = respostaOriginal.substring(startIndex, endIndex + 1);
        
        // 4. Decodifica a string JSON extraída
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } else {
        // Se não conseguiu encontrar um JSON válido, lança um erro.
        throw FormatException("Não foi possível encontrar um objeto JSON válido na resposta da API.");
      }
    }
  } catch (e) {
    print("Erro ao analisar o diálogo ou decodificar o JSON: $e");
    // Imprime a resposta original para sabermos o que causou o erro
    print("Resposta original da API que causou o erro: $respostaOriginal");
  }

  // Retorna um mapa vazio em caso de qualquer erro.
  return {};
}


void _gerenciarTransicaoDeFase(Map<String, dynamic> analise, String respostaChatbot) {
  ChatPhase proximaFase = _currentPhase; // Começa com a fase atual

  switch (_currentPhase) {
    case ChatPhase.explorar:
      // Se o analisador encontrou um evento chave, muda para a fase de rotular.
      if (analise['evento_chave_identificado'] == 'SIM') {
        proximaFase = ChatPhase.rotular;
        print("MUDANÇA DE FASE: explorar -> rotular");
      }
      break;

    case ChatPhase.rotular:
      // A transição aqui é mais complexa. Acontece quando todas as emoções forem
      // abordadas. Para simplificar, vamos imaginar uma condição.
      bool todasEmpatizadas = true;
      if (analise.containsKey('emocoes_identificadas')) {
        List<dynamic> emocoes = analise['emocoes_identificadas'];
        if (emocoes.isEmpty) {
          todasEmpatizadas = false; // Se não identificou emoção, não pode avançar
        }
        for (var emocaoInfo in emocoes) {
          if (emocaoInfo['chatbot_empatizou'] == 'NÃO') {
            todasEmpatizadas = false;
            break;
          }
        }
      } else {
        todasEmpatizadas = false;
      }
      
      if (todasEmpatizadas) {
        // DECIDIR ENTRE BUSCA (negativo) E GRAVACAO (positivo)
        // Esta é uma lógica que você pode refinar. Por exemplo, detectar palavras negativas.
        // Por enquanto, vamos para a fase de busca como padrão.
        proximaFase = ChatPhase.busca;
        print("MUDANÇA DE FASE: rotular -> busca");
      }
      break;

    case ChatPhase.busca:
      // Se o analisador indicar que uma solução foi encontrada.
      if (analise['solucao_proposta_pelo_usuario'] == 'SIM') {
        proximaFase = ChatPhase.compartilhar;
        print("MUDANÇA DE FASE: busca -> compartilhar");
      }
      break;
      
    case ChatPhase.gravacao:
      // Se o analisador indicar que o chatbot já deu o exemplo de diário.
      if (analise['chatbot_ja_deu_exemplo'] == 'SIM') {
        proximaFase = ChatPhase.compartilhar;
        print("MUDANÇA DE FASE: gravacao -> compartilhar");
      }
      break;

    case ChatPhase.compartilhar:
      // Se o analisador indicar que o usuário não quer uma nova conversa.
      if (analise['usuario_deseja_nova_conversa'] == 'NÃO') {
        // Fim da conversa, não muda de fase, pode até mostrar uma mensagem de "tchau".
      } else if (analise['usuario_deseja_nova_conversa'] == 'SIM') {
        // Volta para o início para discutir um novo evento.
        proximaFase = ChatPhase.explorar;
        print("REINICIANDO FLUXO: compartilhar -> explorar");
      }
      break;
  }

  // Atualiza o estado da fase, se ela mudou.
  if (proximaFase != _currentPhase) {
    setState(() {
      _currentPhase = proximaFase;
    });
  }
}
Future<void> sendMessage() async {
  final message = _userInput.text;
  if (message.isEmpty) return;

  setState(() {
    _messages.add(Message(isUser: true, message: message, date: DateTime.now()));
    _userInput.clear();
  });

  try {
    // =======================================================
    // PASSO 1: CHAMAR O ANALISADOR
    // =======================================================
    String dialogoHistorico = _messages.map((m) => "${m.isUser ? 'User' : 'Chatbot'}: ${m.message}").join('\n');
    
    // Chamamos o analisador com o histórico e a fase atual para obter o JSON de análise.
    Map<String, dynamic> analise = await analisarDialogo(dialogoHistorico, _currentPhase);
    print("FASE ATUAL: $_currentPhase");
    print("RESULTADO DA ANÁLISE: $analise");


    // =======================================================
    // PASSO 2: GERAR INSTRUÇÕES DINÂMICAS (com base na análise)
    // =======================================================
    String instrucaoDinamica = "";

    // Lógica para a fase ROTULAR: verifica se há emoções para empatizar.
    if (_currentPhase == ChatPhase.rotular && analise.containsKey('emocoes_identificadas')) {
      List<dynamic> emocoes = analise['emocoes_identificadas'];
      for (var emocaoInfo in emocoes) {
        if (emocaoInfo['chatbot_empatizou'] == 'NÃO') {
          instrucaoDinamica = "Instrução Urgente: Empatize especificamente com a emoção '${emocaoInfo['emocao']}' que o usuário acabou de mencionar.";
          break; // Para na primeira emoção que precisa de empatia.
        }
      }
    }
    // Adicione aqui a lógica para outras fases se precisar de instruções dinâmicas.


    // =======================================================
    // PASSO 3: MONTAR O PROMPT FINAL PARA O CHATBOT PRINCIPAL
    // =======================================================
    String promptBase = AppPrompts.phasePrompts[_currentPhase]!;
    String regras = AppPrompts.regrasGerais;
    
    String promptFinal = """
      $promptBase
      $regras
      
      $instrucaoDinamica

      Histórico da Conversa:
      $dialogoHistorico
      
      Chatbot:
    """;
//Print para Debug da conversa
//void printLongText(String text, {int chunkSize = 1000}) {
//   for (int i = 0; i < text.length; i += chunkSize) {
//     print(text.substring(i, i + chunkSize > text.length ? text.length : i + chunkSize));
//   }
// }
// printLongText(dialogoHistorico);
    // =======================================================
    // PASSO 4: CHAMAR O CHATBOT PRINCIPAL COM O PROMPT INTELIGENTE
    // =======================================================
    final response = await modeloPrincipal.generateContent([
      Content.text(promptFinal),
    ]);
    

    final respostaChatbot = response.text ?? "Desculpe, não consegui processar a resposta.";

    setState(() {
      _messages.add(Message(
          isUser: false,
          message: respostaChatbot,
          date: DateTime.now()));
    });
    

    // =======================================================
    // PASSO 5: GERENCIAR A TRANSIÇÃO PARA A PRÓXIMA FASE
    // =======================================================
    // Esta função usa o resultado da análise para decidir se deve mudar de fase.
    _gerenciarTransicaoDeFase(analise, respostaChatbot);

  } catch (e) {
    setState(() {
      _messages.add(Message(
          isUser: false,
          message: "Desculpe, ocorreu um erro. código: $e",
          date: DateTime.now()));
    });
  }
}
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.8), BlendMode.dstATop),
            image: NetworkImage('https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEigDbiBM6I5Fx1Jbz-hj_mqL_KtAPlv9UsQwpthZIfFLjL-hvCmst09I-RbQsbVt5Z0QzYI_Xj1l8vkS8JrP6eUlgK89GJzbb_P-BwLhVP13PalBm8ga1hbW5pVx8bswNWCjqZj2XxTFvwQ__u4ytDKvfFi5I2W9MDtH3wFXxww19EVYkN8IzIDJLh_aw/s1920/space-soldier-ai-wallpaper-4k.webp'),
            fit: BoxFit.cover
          )
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
                child: ListView.builder(itemCount:_messages.length,itemBuilder: (context,index){
                  final message = _messages[index];
                  return Messages(isUser: message.isUser, message: message.message, date: DateFormat('HH:mm').format(message.date));
                })
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 15,
                    child: TextFormField(
                      style: TextStyle(color: Colors.white),
                      controller: _userInput,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        label: Text('Enter Your Message')
                      ),
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    padding: EdgeInsets.all(12),
                      iconSize: 30,
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(Colors.black),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        shape: WidgetStateProperty.all(CircleBorder())
                      ),
                      onPressed: (){
                      sendMessage();
                      },
                      icon: Icon(Icons.send))
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class Message{
  final bool isUser;
  final String message;
  final DateTime date;

  Message({ required this.isUser, required this.message, required this.date});
}

class Messages extends StatelessWidget {

  final bool isUser;
  final String message;
  final String date;

  const Messages(
      {
        super.key,
        required this.isUser,
        required this.message,
        required this.date
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15),
      margin: EdgeInsets.symmetric(vertical: 15).copyWith(
        left: isUser ? 100:10,
        right: isUser ? 10: 100
      ),
      decoration: BoxDecoration(
        color: isUser ? Colors.blueAccent : Colors.grey.shade400,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          bottomLeft: isUser ? Radius.circular(10): Radius.zero,
          topRight: Radius.circular(10),
          bottomRight: isUser ? Radius.zero : Radius.circular(10)
        )
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(fontSize: 16,color: isUser ? Colors.white: Colors.black),
          ),
          Text(
            date,
            style: TextStyle(fontSize: 10,color: isUser ? Colors.white: Colors.black,),
          )
        ],
      ),
    );
  }
}
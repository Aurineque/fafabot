import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '/constants/prompts.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

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
  final List<Message> _messages = [];
  ChatPhase _currentPhase = ChatPhase.explorar;

  late GenerativeModel modeloPrincipal;
  late GenerativeModel modeloAnalisador;

  // Variáveis de estado para o protocolo de intervenção
  String _questionarioAplicado = '';
  int _indicePerguntaAtual = 0;
  int _pontuacaoQuestionario = 0;
  Map<String, dynamic> _dadosColetadosProtocolo = {};

  bool _isLoading = true;
  Map<String, dynamic> _baseDeConhecimento = {};
  static const List<String> _emocoesDeValidacao = ['medo', 'angústia'];

  @override
  void initState() {
    super.initState();
    modeloPrincipal = GenerativeModel(
      model: 'gemini-1.5-pro-latest',
      apiKey: dotenv.env['API_KEY_principal']!,
    );
    modeloAnalisador = GenerativeModel(
      model: 'gemini-1.5-pro-latest',
      apiKey: dotenv.env['API_KEY_secundario']!,
    );
    print("initState: Chamando _carregarBaseDeConhecimento...");
    _carregarBaseDeConhecimento();
  }

  Future<void> _carregarBaseDeConhecimento() async {
    try {
      print("Iniciando o carregamento do assets/knowledge_base.json...");
      final String response = await rootBundle.loadString('assets/knowledge_base.json');
      print("Arquivo JSON lido com sucesso.");
      final data = json.decode(response);
      print("JSON decodificado com sucesso.");

      setState(() {
        _baseDeConhecimento = data;
        _isLoading = false;
        print("Base de conhecimento carregada e _isLoading definido como false.");
        _messages.add(Message(
          isUser: false,
          message: "Olá! Eu sou a Fafa, sua amiga para conversar. 😊 Para começar, qual é o seu nome e quantos anos você tem?",
          date: DateTime.now(),
        ));
      });
    } catch (e) {
      print("!!!!!!!!!! ERRO CRÍTICO AO CARREGAR A BASE DE CONHECIMENTO !!!!!!!!!!");
      print("Erro: $e");
    }
  }

  Future<Map<String, dynamic>> analisarDialogo(String dialogoHistorico, ChatPhase faseAtual) async {
    // Mapeia cada fase ao seu respectivo prompt de análise
    const Map<ChatPhase, String> promptsAnalisador = {
      ChatPhase.explorar: AppPrompts.analisadorPromptExplorar,
      ChatPhase.rotular: AppPrompts.analisadorPromptRotular,
      ChatPhase.busca: AppPrompts.analisadorPromptBusca,
      ChatPhase.gravacao: AppPrompts.analisadorPromptGravacao,
      ChatPhase.validacao: AppPrompts.analisadorPromptValidacao,
      ChatPhase.questionario: AppPrompts.analisadorPromptQuestionario,
      ChatPhase.preferencias: AppPrompts.analisadorPromptPreferencias,
      ChatPhase.recomendacao: AppPrompts.analisadorPromptRecomendacao,
      ChatPhase.compartilhar: AppPrompts.analisadorPromptCompartilhar,
      ChatPhase.compartilharAprimorado: AppPrompts.analisadorPromptCompartilharAprimorado,
    };

    final promptAnalisador = promptsAnalisador[faseAtual];

    if (promptAnalisador == null) {
      print("AVISO: Nenhum prompt de análise definido para a fase $faseAtual");
      return {};
    }

    final promptCompleto = promptAnalisador + dialogoHistorico;

    try {
      final response = await modeloAnalisador.generateContent([Content.text(promptCompleto)]);
      if (response.text != null) {
        final int startIndex = response.text!.indexOf('{');
        final int endIndex = response.text!.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1) {
          final String jsonString = response.text!.substring(startIndex, endIndex + 1);
          return jsonDecode(jsonString) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print("Erro ao analisar diálogo na fase $faseAtual: $e");
    }
    return {};
  }

  void _gerenciarTransicaoDeFase(Map<String, dynamic> analise) {
    ChatPhase proximaFase = _currentPhase;

    switch (_currentPhase) {
      case ChatPhase.explorar:
        if (analise['evento_chave_identificado'] == 'SIM') {
          proximaFase = ChatPhase.rotular;
        }
        break;

      case ChatPhase.rotular:
        bool podeAvancar = false;
        if (analise.containsKey('emocoes_identificadas')) {
          List<dynamic> emocoes = analise['emocoes_identificadas'];
          if (emocoes.isNotEmpty) {
            podeAvancar = emocoes.every((emocao) => emocao['chatbot_empatizou'] == 'SIM');
          }
        }
        if (podeAvancar) {
          final List<dynamic> emocoes = analise['emocoes_identificadas'];
          final bool contemEmocaoNegativa = emocoes.any((e) => e['polaridade'] == 'negativa');
          if (contemEmocaoNegativa) {
            final bool deveIrParaValidacao = emocoes.where((e) => e['polaridade'] == 'negativa').any((e) => _emocoesDeValidacao.contains(e['emocao_normalizada']));
            if (deveIrParaValidacao) {
              proximaFase = ChatPhase.validacao;
            } else {
              proximaFase = ChatPhase.busca;
            }
          } else {
            proximaFase = ChatPhase.gravacao;
          }
        }
        break;

      case ChatPhase.validacao:
        final dados = analise['dados_coletados'];
        if (dados?['resposta_energia'] != null && dados?['resposta_prazer'] != null) {
          setState(() {
            _dadosColetadosProtocolo = {
              'resposta_energia': dados['resposta_energia'],
              'resposta_prazer': dados['resposta_prazer'],
            };
            _questionarioAplicado = (dados['resposta_energia'] < 0) ? 'phq9_tristeza' : 'gad7_medo';
            _indicePerguntaAtual = 0;
            _pontuacaoQuestionario = 0;
          });
          proximaFase = ChatPhase.questionario;
        }
        break;

      case ChatPhase.questionario:
        final List<dynamic>? todasAsPerguntas = _baseDeConhecimento['questionarios']?[_questionarioAplicado]?['perguntas'];
        if (todasAsPerguntas != null && _indicePerguntaAtual+1 >= todasAsPerguntas.length) {
          proximaFase = ChatPhase.preferencias;
        }
        break;

      case ChatPhase.preferencias:
        final dados = analise['dados_coletados'];
        if (dados?['preferencia_tipo'] != null && dados?['preferencia_tempo'] != null) {
          setState(() {
            _dadosColetadosProtocolo['preferencia_tipo'] = dados['preferencia_tipo'];
            _dadosColetadosProtocolo['preferencia_tempo'] = dados['preferencia_tempo'];
          });
          proximaFase = ChatPhase.recomendacao;
        }
        break;

      case ChatPhase.recomendacao:
        if (analise['dados_coletados']?['recomendacao_feita'] == 'SIM') {
          proximaFase = (_pontuacaoQuestionario > 9) ? ChatPhase.compartilharAprimorado : ChatPhase.compartilhar;
        }
        break;
      
      case ChatPhase.busca:
        if (analise['solucao_proposta_pelo_usuario'] == 'SIM') {
          // Se o usuário propôs uma solução, vamos para a fase de gravação.
          proximaFase = ChatPhase.compartilhar;
        } 
        break;

      case ChatPhase.gravacao:
        if (analise['chatbot_ja_incentivou_diario'] == 'SIM' && analise['chatbot_ja_deu_exemplo'] == 'SIM') {
          proximaFase = ChatPhase.compartilhar;
        } 
        break;

      case ChatPhase.compartilhar:
      if (analise['usuario_deseja_nova_conversa'] == 'SIM') {
          // Em vez de apenas mudar a fase, chamamos a função que reinicia TUDO.
          _reiniciarConversa();
          // Como a função de reinício já atualiza o estado e limpa a tela,
          // não precisamos definir uma `proximaFase`. A função já fez o trabalho.
          return; // Retorna para evitar a lógica de setState no final da função.
        }
        break;
      case ChatPhase.compartilharAprimorado:
        if (analise['usuario_deseja_nova_conversa'] == 'SIM') {
          // Em vez de apenas mudar a fase, chamamos a função que reinicia TUDO.
          _reiniciarConversa();
          // Como a função de reinício já atualiza o estado e limpa a tela,
          // não precisamos definir uma `proximaFase`. A função já fez o trabalho.
          return; // Retorna para evitar a lógica de setState no final da função.
        }
        break;
    }

    if (proximaFase != _currentPhase) {
      print("MUDANÇA DE FASE: $_currentPhase -> $proximaFase");
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

    // Se estivermos no meio de um questionário, o código Dart controla.
    if (_currentPhase == ChatPhase.questionario) {
      _processarRespostaEAvancarQuestionario(message);
      return; // Impede que o fluxo da IA continue
    }

    try {
      String dialogoHistorico = _messages.map((m) => "${m.isUser ? 'User' : 'Chatbot'}: ${m.message}").join('\n');
      Map<String, dynamic> analise = await analisarDialogo(dialogoHistorico, _currentPhase);
      
      print("FASE ATUAL: $_currentPhase");
      print("RESULTADO DA ANÁLISE: $analise");

      String instrucaoDinamica = "";
      if (_currentPhase == ChatPhase.rotular && analise.containsKey('emocoes_identificadas')) {
        List<dynamic> emocoes = analise['emocoes_identificadas'];
        for (var emocaoInfo in emocoes) {
          if (emocaoInfo['chatbot_empatizou'] == 'NÃO') {
            instrucaoDinamica = "Instrução Urgente: Empatize especificamente com a emoção '${emocaoInfo['emocao_usuario']}' que o usuário acabou de mencionar.";
            break;
          }
        }
      } else if (_currentPhase == ChatPhase.recomendacao) {
        instrucaoDinamica = "Instrução Urgente: Gere uma recomendação com base nos seguintes dados coletados: $_dadosColetadosProtocolo e a pontuação do questionário que foi $_pontuacaoQuestionario";
      }

      String promptBase = AppPrompts.phasePrompts[_currentPhase]!;
      String regras = AppPrompts.regrasGerais;
      String promptFinal = """
        $promptBase
        $regras
        $instrucaoDinamica
        Histórico da Conversa:
        $dialogoHistorico
        Fafa:
      """;

      final response = await modeloPrincipal.generateContent([Content.text(promptFinal)]);
      final respostaChatbot = response.text ?? "Desculpe, não consegui processar a resposta.";

      setState(() {
        _messages.add(Message(isUser: false, message: respostaChatbot, date: DateTime.now()));
      });

      _gerenciarTransicaoDeFase(analise);

      // Se a nova fase é questionário, inicia o processo
      if (_currentPhase == ChatPhase.questionario) {
        _iniciarQuestionario();
      }

    } catch (e) {
      setState(() {
        _messages.add(Message(isUser: false, message: "Desculpe, ocorreu um erro. código: $e", date: DateTime.now()));
      });
    }
  }

  void _iniciarQuestionario() {
    print("Iniciando a primeira pergunta do questionário: $_questionarioAplicado");
    _fazerProximaPergunta();
  }

  void _fazerProximaPergunta() {
    final List<dynamic>? todasAsPerguntas = _baseDeConhecimento['questionarios']?[_questionarioAplicado]?['perguntas'];

    if (todasAsPerguntas != null && _indicePerguntaAtual < todasAsPerguntas.length) {
      final pergunta = todasAsPerguntas[_indicePerguntaAtual]['texto'];
      final opcoes = (_baseDeConhecimento['questionarios']['opcoes_resposta'] as List).map((opt) => opt['texto'] as String).join('", "');
      final mensagemBot = "Pergunta ${_indicePerguntaAtual + 1}: $pergunta\n\nLembre-se que as opções são: \"$opcoes\".";
      
      setState(() {
        _messages.add(Message(isUser: false, message: mensagemBot, date: DateTime.now()));
      });
    } else {
      // O questionário terminou, vamos acionar a transição de fase
      print("Fim do questionário. Pontuação total: $_pontuacaoQuestionario. Acionando transição.");
      // Simula uma análise para forçar a transição
      _gerenciarTransicaoDeFase({}); 
    }
  }

  void _processarRespostaEAvancarQuestionario(String respostaUsuario) {
    final List<dynamic> opcoes = _baseDeConhecimento['questionarios']['opcoes_resposta'];
    int pontos = 0;
    
    // Procura a opção que corresponde à resposta do usuário (de forma flexível)
    for (var opcao in opcoes) {
      if (respostaUsuario.toLowerCase().contains(opcao['texto'].toLowerCase())) {
        pontos = opcao['pontos'];
        break;
      }
    }
    
    _pontuacaoQuestionario += pontos;

    setState(() {
      _indicePerguntaAtual++;
    });

    _fazerProximaPergunta(); // Chama a próxima pergunta ou finaliza.
  }

  void _reiniciarConversa() {
    setState(() {
      // 1. Limpa o histórico de mensagens
      _messages.clear();

      // 2. Adiciona a mensagem inicial do chatbot
      _messages.add(Message(
        isUser: false,
        message: "Olá! Eu sou a Fafa, sua amiga para conversar. 😊 Para começar, qual é o seu nome e quantos anos você tem?",
        date: DateTime.now(),
      ));

      // 3. Reseta a máquina de estados para a fase inicial
      _currentPhase = ChatPhase.explorar;

      // 4. Limpa todas as variáveis de estado da conversa anterior
      _questionarioAplicado = '';
      _indicePerguntaAtual = 0;
      _pontuacaoQuestionario = 0;
      _dadosColetadosProtocolo = {};
    });
    print("CONVERSA REINICIADA. Estado zerado.");
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    // A lógica de carregamento é aplicada aqui, no 'body' do Scaffold.
    body: _isLoading
        // 1. SE _isLoading for 'true', mostra um círculo de progresso no centro.
        //    A imagem de fundo não é carregada ainda para manter a tela limpa.
        ? const Center(
            child: CircularProgressIndicator(),
          )
        // 2. SE _isLoading for 'false' (ou seja, o JSON já carregou),
        //    constrói a interface normal do seu chat.
        : Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.8), BlendMode.dstATop),
                image: const NetworkImage('https://i.pinimg.com/736x/f5/5e/be/f55ebeb39d8ac0bc43467e6ec983a1bf.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true, // Adicionar 'reverse: true' faz o chat começar de baixo
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      // Acessa a lista de forma invertida para mostrar a última mensagem no final
                      final message = _messages.reversed.toList()[index];
                      return Messages(
                        isUser: message.isUser,
                        message: message.message,
                        date: DateFormat('HH:mm').format(message.date),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 15,
                        child: TextFormField(
                          style: const TextStyle(color: Colors.white),
                          controller: _userInput,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            label: const Text('Enter Your Message'),
                            labelStyle: const TextStyle(color: Colors.white70), // Melhora a legibilidade
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        padding: const EdgeInsets.all(12),
                        iconSize: 30,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(Colors.black),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                          shape: WidgetStateProperty.all(const CircleBorder()),
                        ),
                        onPressed: () {
                          sendMessage();
                        },
                        icon: const Icon(Icons.send),
                      )
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
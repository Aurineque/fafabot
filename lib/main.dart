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

  int _pontuacaoQuestionario = 0;
  bool _isLoading = true;
  Map<String, dynamic> _baseDeConhecimento = {};
  static const List<String> _emocoesDeValidacao = [
    'medo', 'angústia', 'decepção'
  ];

Future<void> _carregarBaseDeConhecimento() async {
  try {
    print("Iniciando o carregamento do assets/knowledge_base.json...");
    // Acessa o arquivo JSON nos assets
    final String response = await rootBundle.loadString('assets/knowledge_base.json');
    print("Arquivo JSON lido com sucesso.");

    // Decodifica o JSON
    final data = json.decode(response);
    print("JSON decodificado com sucesso.");

    // Atualiza o estado
    setState(() {
      _baseDeConhecimento = data;
      _isLoading = false; // <-- O loading só termina SE tudo der certo
      print("Base de conhecimento carregada e _isLoading definido como false.");

      _messages.add(Message(
        isUser: false,
        message: "Olá! Eu sou a Fafa, sua amiga para conversar. 😊 Para começar, qual é o seu nome e quantos anos você tem?",
        date: DateTime.now(),
      ));
    });
  } catch (e) {
    // SE OCORRER QUALQUER ERRO, ELE SERÁ IMPRESSO AQUI!
    print("!!!!!!!!!! ERRO CRÍTICO AO CARREGAR A BASE DE CONHECIMENTO !!!!!!!!!!");
    print("Erro: $e");
    // Opcional: você pode querer parar o loading e mostrar uma mensagem de erro na tela
    // setState(() {
    //   _isLoading = false; 
    //   // Adicione uma variável para mostrar uma mensagem de erro na UI
    // });
  }
}

  @override
  void initState() {
    super.initState();
    modeloPrincipal = GenerativeModel(
      model: 'gemini-1.5-pro-latest', // para conversa
      apiKey: dotenv.env['API_KEY_principal']!,
    );
    modeloAnalisador = GenerativeModel(
      model: 'gemini-1.5-pro-latest', // para análise/JSON
      apiKey: dotenv.env['API_KEY_secundario']!,
    );
    // 3. Carrega a base de conhecimento
    print("initState: Chamando _carregarBaseDeConhecimento...");
    _carregarBaseDeConhecimento();
  }

Future<Map<String, dynamic>> analisarDialogo(String dialogoHistorico, ChatPhase faseAtual) async {
    String? promptAnalisador;
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
      case ChatPhase.protocoloIntervencao: // <-- Novo caso
        promptAnalisador = AppPrompts.analisadorPromptProtocolo;
        break;
      case ChatPhase.compartilhar:
        promptAnalisador = AppPrompts.analisadorPromptCompartilhar;
        break;
      case ChatPhase.compartilharAprimorado:
        promptAnalisador = AppPrompts.analisadorPromptCompartilharAprimorado;
        break;
    }

    final promptCompleto = promptAnalisador + dialogoHistorico;
    // (Sua lógica de chamada do analisador e extração de JSON continua aqui)
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
        print("Erro ao analisar diálogo: $e");
    }
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
  // O "porteiro": esta lógica continua a mesma e é essencial.
  // Só avançamos de fase se o chatbot já empatizou com todas as emoções identificadas.
  bool podeAvancar = false;
  if (analise.containsKey('emocoes_identificadas')) {
    List<dynamic> emocoes = analise['emocoes_identificadas'];
    if (emocoes.isNotEmpty) {
      podeAvancar = emocoes.every((emocao) => emocao['chatbot_empatizou'] == 'SIM');
    }
  }

  // Se a condição para avançar foi atendida, aplicamos a nova lógica de ramificação.
  if (podeAvancar) {
    final List<dynamic> emocoes = analise['emocoes_identificadas'];

    // 1. PRIMEIRO, VERIFICAMOS SE EXISTE QUALQUER EMOÇÃO COM POLARIDADE NEGATIVA.
    final bool contemEmocaoNegativa = emocoes.any((e) => e['polaridade'] == 'negativa');

    if (contemEmocaoNegativa) {
      // Se existe pelo menos uma emoção negativa, vamos analisá-la.

      // 2. AGORA, VERIFICAMOS SE ALGUMA DAS EMOÇÕES NEGATIVAS É UMA DAS ESPECIAIS ('medo', 'angústia', 'decepção').
      //    Usamos .where() para filtrar apenas as emoções negativas
      //    e .any() para checar se alguma delas está na nossa lista de validação.
      final bool deveIrParaValidacao = emocoes
          .where((e) => e['polaridade'] == 'negativa')
          .any((e) => _emocoesDeValidacao.contains(e['emocao_normalizada']));

      if (deveIrParaValidacao) {
        // CAMINHO 3: Emoções de Alerta Específicas
        proximaFase = ChatPhase.protocoloIntervencao;
        print("RAMIFICAÇÃO: Emoção de validação ('medo', 'angústia', 'decepção') detectada. Indo para o Caminho 3 -> validacao");
      } else {
        // CAMINHO 2: Emoções Negativas Gerais
        // Se há emoções negativas, mas nenhuma delas está na lista de validação especial.
        proximaFase = ChatPhase.busca;
        print("RAMIFICAÇÃO: Emoções negativas gerais detectadas. Indo para o Caminho 2 -> busca");
      }

    } else {
      // CAMINHO 1: Apenas Emoções Positivas
      // Se o .any() não encontrou nenhuma emoção com polaridade negativa,
      // significa que todas são positivas.
      proximaFase = ChatPhase.gravacao;
      print("RAMIFICAÇÃO: Apenas emoções positivas detectadas. Indo para o Caminho 1 -> gravacao");
    }
  }
  break;
  
    case ChatPhase.protocoloIntervencao:
  // Se o analisador indicar que o protocolo foi concluído...
  if (analise['sub_etapa_atual'] == 'concluido') {
    // Guarda a pontuação final que o analisador extraiu
    final int pontuacaoFinal = analise['dados_coletados']?['pontuacao_total'] ?? 0;
    
    setState(() {
      _pontuacaoQuestionario = pontuacaoFinal;
    });

    // LÓGICA DE DECISÃO PRINCIPAL!
    // Se a pontuação for maior que 9, vai para a fase aprimorada.
    if (pontuacaoFinal > 9) {
      proximaFase = ChatPhase.compartilharAprimorado;
      print("PONTUAÇÃO ALTA ($pontuacaoFinal > 9). Indo para -> compartilharAprimorado");
    } else {
      // Caso contrário, vai para a fase padrão.
      proximaFase = ChatPhase.compartilhar;
      print("PONTUAÇÃO BAIXA ($pontuacaoFinal <= 9). Indo para -> compartilhar");
    }
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
      if (analise['usuario_deseja_nova_conversa'] == 'NÃO' && analise['discutido_compartilhar_com_pais'] == 'SIM') {
        // Fim da conversa, não muda de fase, pode até mostrar uma mensagem de "tchau".
      } else if (analise['usuario_deseja_nova_conversa'] == 'SIM' && analise['discutido_compartilhar_com_pais'] == 'SIM') {
        // Volta para o início para discutir um novo evento.
        proximaFase = ChatPhase.explorar;
        print("REINICIANDO FLUXO: compartilhar -> explorar");
      }
      break;

    case ChatPhase.compartilharAprimorado:
      
      if (analise['usuario_deseja_nova_conversa'] == 'NÃO' && analise['discutido_compartilhar_com_pais'] == 'SIM' && analise['discutido_compartilhar_com_profissional'] == 'SIM') {
        // Fim da conversa, não muda de fase, pode até mostrar uma mensagem de "tchau".
      } else if (analise['usuario_deseja_nova_conversa'] == 'SIM' && analise['discutido_compartilhar_com_pais'] == 'SIM' && analise['discutido_compartilhar_com_profissional'] == 'SIM') {
        // Volta para o início para discutir um novo evento.
        proximaFase = ChatPhase.explorar;
        print("REINICIANDO FLUXO: compartilhar -> explorar");
      }
      break;
  }

  if (proximaFase != _currentPhase) {
  setState(() {
    _currentPhase = proximaFase;
  });
 }
 }

Future<void> sendMessage() async {
  final message = _userInput.text;
  if (message.isEmpty) return;

  // Adiciona a mensagem do usuário à tela imediatamente.
  setState(() {
    _messages.add(Message(isUser: true, message: message, date: DateTime.now()));
    _userInput.clear();
  });
  // =======================================================
  // O FLUXO PRINCIPAL (CONVERSA COM IA) CONTINUA ABAIXO
  // A mensagem do usuário já foi adicionada à tela.
  // =======================================================
  try {
    // PASSO 1: CHAMAR O ANALISADOR
    String dialogoHistorico = _messages.map((m) => "${m.isUser ? 'User' : 'Chatbot'}: ${m.message}").join('\n');
    Map<String, dynamic> analise = await analisarDialogo(dialogoHistorico, _currentPhase);
    print("FASE ATUAL: $_currentPhase");
    print("RESULTADO DA ANÁLISE: $analise");

    // PASSO 2: GERAR INSTRUÇÕES DINÂMICAS
    String instrucaoDinamica = "";
    if (_currentPhase == ChatPhase.rotular && analise.containsKey('emocoes_identificadas')) {
      List<dynamic> emocoes = analise['emocoes_identificadas'];
      for (var emocaoInfo in emocoes) {
        if (emocaoInfo['chatbot_empatizou'] == 'NÃO') {
          instrucaoDinamica = "Instrução Urgente: Empatize especificamente com a emoção '${emocaoInfo['emocao']}' que o usuário acabou de mencionar.";
          break;
        }
      }
    }
    if (_currentPhase == ChatPhase.protocoloIntervencao) {
  final subEtapa = analise['sub_etapa_atual'] ?? 'validacao';
  final dadosColetados = analise['dados_coletados'];
  
  instrucaoDinamica = "Instrução: Foque na sub-etapa '$subEtapa' do protocolo.";

  // LÓGICA PRINCIPAL PARA O QUESTIONÁRIO
  if (subEtapa == 'questionario' && dadosColetados != null) {
    // 1. Identifica qual questionário está sendo aplicado
    final String? questionarioAplicado = dadosColetados['questionario_aplicado'];
    if (questionarioAplicado != null) {
      
      // 2. Conta quantas respostas já foram dadas para saber qual é a próxima pergunta
      final List<dynamic> respostasDadas = dadosColetados['respostas_questionario'] ?? [];
      final int proximoIndice = respostasDadas.length;

      // 3. Carrega a lista de todas as perguntas do JSON
      final List<dynamic>? todasAsPerguntas = _baseDeConhecimento['questionarios']?[questionarioAplicado]?['perguntas'];

      if (todasAsPerguntas != null && proximoIndice < todasAsPerguntas.length) {
        // 4. Pega o texto da pergunta correta
        final String proximaPerguntaTexto = todasAsPerguntas[proximoIndice]['texto'];

        // 5. Cria a instrução dinâmica e injeta a pergunta
        instrucaoDinamica = "Instrução Urgente: A sub-etapa é 'questionario'. "
                            "Sua única tarefa é fazer a seguinte pergunta ao usuário de forma amigável: "
                            "'$proximaPerguntaTexto'";
      }
    }
  }

  // Lógica para a recomendação continua a mesma
  if (subEtapa == 'recomendacao' && dadosColetados != null) {
    final tipo = dadosColetados['preferencia_tipo'];
    final tempo = dadosColetados['preferencia_tempo'];
    final teste = dadosColetados['questionario_aplicado'];
    instrucaoDinamica = "Instrução Urgente: A sub-etapa é 'recomendacao'. "
                        "O usuário sentiu uma emoção de '$teste'. "
                        "Ele(a) prefere '$tipo' e tem '$tempo' minutos. "
                        "Use a BASE DE CONHECIMENTO para escolher e apresentar a melhor atividade.";
  }
}

    // PASSO 3: MONTAR O PROMPT FINAL
    String promptFinal; // Declare a variável aqui

    final subEtapa = analise['sub_etapa_atual'] ?? '';


  if (_currentPhase == ChatPhase.protocoloIntervencao && subEtapa == 'questionario' && instrucaoDinamica.isNotEmpty) {
    
    print("Montando prompt SIMPLIFICADO para a sub-etapa do questionário.");
    promptFinal = """
      Seu papel: Você é a Fafa, uma amiga que está aplicando um questionário.
      Sua tarefa é apenas fazer a pergunta que está na instrução urgente, de forma natural e amigável, e apresentar as opções de resposta.
      Lembre-se de sempre informar que as opções de resposta são: "De forma alguma", "Vários dias", "Mais da metade dos dias", "Quase todos os dias".
      
      ${AppPrompts.regrasGerais}

      $instrucaoDinamica 
      
      Histórico da Conversa:
      $dialogoHistorico
      Chatbot:
    """;

  } else {
    // Para todas as outras fases e sub-etapas, usamos o prompt padrão completo
    print("Montando prompt PADRÃO para a fase $_currentPhase e sub-etapa '$subEtapa'.");
    String promptBase = AppPrompts.phasePrompts[_currentPhase]!;
    String regras = AppPrompts.regrasGerais;
    promptFinal = """
      $promptBase
      $regras
      $instrucaoDinamica
      Histórico da Conversa:
      $dialogoHistorico
      Chatbot:
    """;
  }

    // PASSO 4: CHAMAR O CHATBOT PRINCIPAL
    final response = await modeloPrincipal.generateContent([Content.text(promptFinal)]);
    final respostaChatbot = response.text ?? "Desculpe, não consegui processar a resposta.";

    setState(() {
      _messages.add(Message(isUser: false, message: respostaChatbot, date: DateTime.now()));
    });
    
    // PASSO 5: GERENCIAR A TRANSIÇÃO DE FASE
    _gerenciarTransicaoDeFase(analise, respostaChatbot);

  } catch (e) {
    setState(() {
      _messages.add(Message(isUser: false, message: "Desculpe, ocorreu um erro. código: $e", date: DateTime.now()));
    });
  }
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
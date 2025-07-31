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

enum TipoQuestionario { gad7_medo, phq9_tristeza, nenhum }

class _ChatScreenState extends State<ChatScreen> {  
  final TextEditingController _userInput = TextEditingController();

  final List<Message> _messages = [];

  ChatPhase _currentPhase = ChatPhase.explorar;

  late GenerativeModel modeloPrincipal;
  late GenerativeModel modeloAnalisador;

  // Emoções que ativam o Caminho 3 (Protocolo Motus Up)
  static const List<String> _emocoesDeValidacao = [
    'medo', 'angústia', 'decepção'
  ];

  TipoQuestionario _proximoQuestionario = TipoQuestionario.nenhum;

  Map<String, dynamic> _baseDeConhecimento = {};
  int _indicePerguntaAtual = 0;
  int _pontuacaoQuestionario = 0;
  bool _questionarioAtivo = false;

  bool _isLoading = true;

  bool _consentimentoQuestionarioObtido = false;

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
  case ChatPhase.validacao:
    promptAnalisador = AppPrompts.analisadorPromptValidacao;
    break;
  case ChatPhase.questionario:
    promptAnalisador = ""; // ou defina um prompt específico se necessário
    break;
  case ChatPhase.preferencias:
    promptAnalisador = ""; // ou defina um prompt específico se necessário
    break;
  case ChatPhase.recomendacao:
    promptAnalisador = ""; // ou defina um prompt específico se necessário
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

 void _processarRespostaQuestionario(String respostaUsuario) {
  // Acessa a lista de opções de resposta do nosso JSON
  final List<dynamic>? opcoes = _baseDeConhecimento['questionarios']?['opcoes_resposta'];
  if (opcoes == null) return;

  // Formata a resposta do usuário para uma comparação mais robusta
  final respostaFormatada = respostaUsuario.toLowerCase().trim();
  int pontosGanhos = 0;

  // Procura pela resposta do usuário nas opções disponíveis
  for (var opcao in opcoes) {
    String textoOpcao = (opcao['texto'] as String).toLowerCase();
    // Usamos .contains() para ser mais flexível com a digitação do usuário
    if (respostaFormatada.contains(textoOpcao)) {
      pontosGanhos = opcao['pontos'];
      break; // Encontrou a correspondência, pode parar o loop
    }
  }

  // Adiciona os pontos encontrados à pontuação total
  setState(() {
    _pontuacaoQuestionario += pontosGanhos;
  });

  // Imprime no console para depuração
  print("Resposta do usuário: '$respostaUsuario' | Pontos adicionados: $pontosGanhos | Pontuação Total: $_pontuacaoQuestionario");
}
 
 void _pedirConsentimentoParaQuestionario() {
  setState(() {
    _messages.add(Message(
      isUser: false,
      message: "Obrigado por me contar como se sente. Para eu entender um pouco melhor, eu gostaria de fazer algumas perguntas rápidas. Tudo bem por você?",
      date: DateTime.now(),
    ));
  });
}

void _fazerProximaPergunta() {
  // 1. Verifica se a base de conhecimento já foi carregada
  if (_baseDeConhecimento.isEmpty) {
    print("ERRO: Base de conhecimento está vazia. Não é possível fazer a pergunta.");
    return;
  }

  // 2. CORREÇÃO: Mapeia o enum para a string correta do JSON
  String chaveQuestionario;
  switch (_proximoQuestionario) {
    case TipoQuestionario.gad7_medo:
      chaveQuestionario = 'gad7_medo';
      break;
    case TipoQuestionario.phq9_tristeza:
      chaveQuestionario = 'phq9_tristeza';
      break;
    default:
      print("ERRO: Nenhum questionário selecionado.");
      return;
  }
  
  print("Procurando perguntas para o questionário: '$chaveQuestionario'");

  // 3. Acessa a lista de perguntas de forma segura
  List<dynamic>? perguntas = _baseDeConhecimento['questionarios']?[chaveQuestionario]?['perguntas'];

  if (perguntas == null || perguntas.isEmpty) {
    print("ERRO: Não foram encontradas perguntas para a chave '$chaveQuestionario'. Verifique seu JSON.");
    return;
  }

  // 4. Lógica para fazer a pergunta ou finalizar
  if (_indicePerguntaAtual < perguntas.length) {
    String textoPergunta = perguntas[_indicePerguntaAtual]['texto'];
    
    print("Fazendo a pergunta de índice $_indicePerguntaAtual: $textoPergunta");

    setState(() {
      _messages.add(Message(
        isUser: false,
        message: "Pergunta ${_indicePerguntaAtual + 1} de ${perguntas.length}: $textoPergunta (Responda com umas das seguintes opções: De forma alguma, Vários dias, Mais da metade dos dias, Quase todos os dias)",
        date: DateTime.now()
      ));
      // AQUI VOCÊ DEVE EXIBIR OS BOTÕES DE RESPOSTA NA TELA
      // Ex: List<dynamic> opcoes = _baseDeConhecimento['questionarios']['opcoes_resposta'];
    });
  } else {
    // Se todas as perguntas foram feitas
    print("Questionário finalizado com pontuação: $_pontuacaoQuestionario");
    setState(() {
      _questionarioAtivo = false;
    });
    _finalizarQuestionarioEAnalisar(); 
  }
}

// Função para quando o questionário acaba
void _finalizarQuestionarioEAnalisar() async {
  // Adiciona uma mensagem de finalização
  setState(() {
     _messages.add(Message(
        isUser: false,
        message: "Obrigada por responder! Sua pontuação foi: $_pontuacaoQuestionario.",
        date: DateTime.now()
      ));
  });

  // Simula uma chamada de sendMessage para acionar a análise e transição de fase
  // (Esta parte pode ser refinada, mas força a próxima etapa)
  String dialogoHistorico = _messages.map((m) => "${m.isUser ? 'User' : 'Chatbot'}: ${m.message}").join('\n');
  Map<String, dynamic> analise = { "questionario_concluido": "SIM" }; // Simula resultado da análise
  _gerenciarTransicaoDeFase(analise, "");
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
        proximaFase = ChatPhase.validacao;
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

// DENTRO DE _gerenciarTransicaoDeFase

  case ChatPhase.validacao:
    print("EXECUTANDO LÓGICA DE TRANSIÇÃO PARA: validacao");
    
    if (analise['validacao_concluida'] == 'SIM') {
      final int? prazer = analise['resposta_prazer'];
      final int? energia = analise['resposta_energia'];
      TipoQuestionario questionarioEscolhido = TipoQuestionario.nenhum;

      if (prazer != null && prazer <= 0) {
        if (energia != null && energia >= 0) {
          questionarioEscolhido = TipoQuestionario.gad7_medo;
        } else {
          questionarioEscolhido = TipoQuestionario.phq9_tristeza;
        }
      }

      if (questionarioEscolhido != TipoQuestionario.nenhum) {
        // Atualiza o estado para preparar o questionário
        if (questionarioEscolhido != TipoQuestionario.nenhum) {
    setState(() {
      _proximoQuestionario = questionarioEscolhido;
      _questionarioAtivo = true;
      _indicePerguntaAtual = 0;
      _pontuacaoQuestionario = 0;
      _consentimentoQuestionarioObtido = false; // <-- GARANTE QUE O CONSENTIMENTO SEJA RESETADO
    });
    proximaFase = ChatPhase.questionario;
    print("MUDANÇA DE FASE: validacao -> questionario");
        }
        proximaFase = ChatPhase.questionario;
        print("MUDANÇA DE FASE: validacao -> questionario");
      } else {
        proximaFase = ChatPhase.busca;
        print("FALLBACK: Respostas de validação não indicam teste. Indo para -> busca");
      }
    }
  break;
    // Case para sair do questionário
    case ChatPhase.questionario:
      print("EXECUTANDO LÓGICA DE TRANSIÇÃO PARA: questionario");
      // A transição será acionada pela função _finalizarQuestionarioEAnalisar
      // quando todas as perguntas forem respondidas.
      if (analise['questionario_concluido'] == 'SIM') {
        proximaFase = ChatPhase.preferencias;
        print("MUDANÇA DE FASE: questionario -> preferencias");
      }
      break;

    case ChatPhase.preferencias:
      print("EXECUTANDO LÓGICA DE TRANSIÇÃO PARA: preferencias");
      // A lógica aqui verificará se as preferências foram coletadas.
      // Ex: if (analise['preferencias_coletadas'] == 'SIM') {
      //   proximaFase = ChatPhase.recomendacao;
      // }
      break;

    case ChatPhase.recomendacao:
      print("EXECUTANDO LÓGICA DE TRANSIÇÃO PARA: recomendacao");
      // A lógica aqui verificará se a recomendação foi feita para então ir para 'compartilhar'.
      // Ex: if (analise['recomendacao_feita'] == 'SIM') {
      //   proximaFase = ChatPhase.compartilhar;
      // }
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

  if (proximaFase != _currentPhase) {
  setState(() {
    _currentPhase = proximaFase;
  });

  // VERIFICA SE A NOVA FASE É O QUESTIONÁRIO E CHAMA A FUNÇÃO RENOMEADA
  if (proximaFase == ChatPhase.questionario) {
    _pedirConsentimentoParaQuestionario();
  }
}
}
// Dentro de _ChatScreenState

Future<void> sendMessage() async {
  final message = _userInput.text;
  if (message.isEmpty) return;

  // Adiciona a mensagem do usuário à tela imediatamente.
  setState(() {
    _messages.add(Message(isUser: true, message: message, date: DateTime.now()));
    _userInput.clear();
  });

  if (_questionarioAtivo) {
  // PRIMEIRO, VERIFICA SE JÁ TEMOS O CONSENTIMENTO
  if (!_consentimentoQuestionarioObtido) {
    final resposta = message.toLowerCase().trim();
    // Verifica se a resposta foi positiva
    if (resposta.contains('sim') || resposta.contains('ok') || resposta.contains('tudo bem') || resposta.contains('pode')) {
      setState(() {
        _consentimentoQuestionarioObtido = true;
      });
      // Consentimento obtido, faz a primeira pergunta do questionário
      _fazerProximaPergunta();
    } else {
      // Se a resposta foi negativa, pula todo o questionário
      setState(() {
        _questionarioAtivo = false;
        _currentPhase = ChatPhase.compartilhar; // Pula para a fase final
      });
      // Inicia a fase de compartilhar com uma mensagem amigável
      _currentPhase = ChatPhase.compartilhar; 
    }
  } else {
    // SE O CONSENTIMENTO JÁ FOI DADO, CONTINUA O QUESTIONÁRIO NORMALMENTE
    print("Modo questionário ativo. Processando resposta para pergunta de índice $_indicePerguntaAtual.");
    _processarRespostaQuestionario(message);
    setState(() {
      _indicePerguntaAtual++;
    });
    _fazerProximaPergunta();
  }
  return; // Para a execução para não chamar a IA
}
  
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

    // PASSO 3: MONTAR O PROMPT FINAL
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
                image: const NetworkImage('https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEigDbiBM6I5Fx1Jbz-hj_mqL_KtAPlv9UsQwpthZIfFLjL-hvCmst09I-RbQsbVt5Z0QzYI_Xj1l8vkS8JrP6eUlgK89GJzbb_P-BwLhVP13PalBm8ga1hbW5pVx8bswNWCjqZj2XxTFvwQ__u4ytDKvfFi5I2W9MDtH3wFXxww19EVYkN8IzIDJLh_aw/s1920/space-soldier-ai-wallpaper-4k.webp'),
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
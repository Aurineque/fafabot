# Fafabot

Fafabot é um chatbot Flutter com integração à IA generativa do Google Gemini e Firebase, focado em acolhimento emocional para crianças.

## Índice

- [Fafabot](#fafabot)
  - [Índice](#índice)
  - [Sobre o Projeto](#sobre-o-projeto)
  - [Funcionalidades](#funcionalidades)
  - [Tecnologias Utilizadas](#tecnologias-utilizadas)
  - [Como Rodar o Projeto](#como-rodar-o-projeto)
  - [Configuração do Ambiente](#configuração-do-ambiente)
  - [Configuração do .env](#configuração-do-env)
  - [Estrutura de Pastas](#estrutura-de-pastas)
  - [Status do Projeto](#status-do-projeto)

---

## Sobre o Projeto

O Fafabot foi desenvolvido como parte de um Trabalho de Conclusão de Curso (TCC) para oferecer acolhimento emocional a crianças por meio de um chatbot interativo. Utilizando IA generativa do Google Gemini, o bot conduz conversas empáticas, aplica questionários e sugere atividades baseadas no contexto emocional do usuário. Todas as interações são armazenadas no Firebase Firestore para análise e acompanhamento.

## Funcionalidades

- Chatbot com IA generativa (Google Gemini)
- Protocolo de acolhimento emocional em múltiplas fases
- Armazenamento de sessões e logs no Firebase Firestore
- Aplicação de questionários dinâmicos (PHQ-9, GAD-7)
- Sugestão de atividades personalizadas
- Interface amigável e adaptada para crianças

## Tecnologias Utilizadas

- [Flutter](https://flutter.dev/)
- [Firebase (Firestore)](https://firebase.google.com/)
- [Google Generative AI (Gemini)](https://ai.google.dev/)
- [intl](https://pub.dev/packages/intl)
- [flutter_dotenv](https://pub.dev/packages/flutter_dotenv)

## Como Rodar o Projeto

1. Clone o repositório:
   ```sh
   git clone https://github.com/seu-usuario/fafabot.git
   cd fafabot
   ```
2. Instale as dependências:
   ```sh
   flutter pub get
   ```
3. Configure o Firebase:
   - Crie um projeto no [Firebase Console](https://console.firebase.google.com/)
   - Adicione um aplicativo Flutter
   - Baixe o arquivo `google-services.json` e coloque na pasta `android/app`
   - Siga as instruções para configurar o Firebase Firestore e autenticação
4. Execute o aplicativo:
   ```sh
   flutter run
   ```

## Configuração do Ambiente

Para desenvolver e rodar este projeto, você precisará de:

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Android Studio](https://developer.android.com/studio) ou outro editor de sua escolha
- Emulador Android ou dispositivo físico para testes

## Configuração do .env

Crie um arquivo `.env` na raiz do projeto com o seguinte conteúdo:

```
API_KEY_principal = "sua-chave-aqui"
API_KEY_secundario = "sua-chave-aqui"
```

## Estrutura de Pastas

- `android/`: Código específico do Android
- `ios/`: Código específico do iOS
- `lib/`: Código Dart do aplicativo

## Status do Projeto

Projeto em desenvolvimento.

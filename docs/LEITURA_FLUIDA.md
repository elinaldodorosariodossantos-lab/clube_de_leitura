# Navegação de leitura

As otimizações usam as APIs atuais, sem alterar banco, regras de acesso ou pontuação.

- A resposta autorizada de início de história passa diretamente para o leitor, uma única vez, na mesma sessão. Abrir uma atividade por URL ou recarregar continua consultando o servidor.
- A abertura da história não aguarda uma atualização geral do painel e não busca novamente o mesmo conteúdo.
- Resultados com identificadores explicitamente nulos indicam uma história intermediária e seguem para a próxima história. A recuperação de resultados de versões anteriores continua disponível quando esses campos não vêm na resposta.
- As respostas ficam visíveis imediatamente e são enviadas em sequência. Avançar para outra pergunta não precisa aguardar o envio anterior.
- Escolhas mais recentes não são sobrescritas por respostas de requisições anteriores. Em caso de falha, os dados pendentes permanecem na sessão e há uma opção de tentar salvar novamente.
- Finalização, mudança de etapa e saída da sessão aguardam a confirmação dos envios. Recarregar com respostas pendentes aciona a proteção contra saída com dados não salvos.
- A virada de página usa uma animação de 120 ms; a entrada de pergunta usa 80 ms. O salvamento sequencial das páginas e a preferência por movimento reduzido permanecem respeitados.

Validação: testes da fila de respostas, navegador com envios retidos e falha de rede simulada, abertura da história sem atualização geral concluída, troca entre histórias sem GET duplicado e recuperação da conquista após recarregar. Esses testes não usam alunos ou dados de produção.

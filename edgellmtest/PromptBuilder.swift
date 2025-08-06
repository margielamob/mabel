//
//  PromptBuilder.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-13.
//

struct PromptBuilder {
    static func translationPrompt(
        sourceText: String,
        sourceLang: String,
        targetLang: String
    ) -> String {
       """
       <bos><start_of_turn>user
       CRITICAL: You must output EXACTLY 7 lines. No more. No less.

       TRANSLATE: \(sourceText)
       FROM: \(sourceLang)
       TO: \(targetLang)

       OUTPUT FORMAT - EXACTLY 7 LINES IN THIS ORDER:
       LINE 1: Translation of input text \(targetLang)
       LINE 2: Context phrase 1 \(sourceLang)
       LINE 3: Context phrase 1 translated \(targetLang)
       LINE 4: Context phrase 2 \(sourceLang)
       LINE 5: Context phrase 2 translated \(targetLang)
       LINE 6: Context phrase 3 \(sourceLang)
       LINE 7: Context phrase 3 translated \(targetLang)

       FORBIDDEN:
       - No bullets (•, -, *)
       - No quotes (" or ')
       - No line numbers
       - No labels
       - No explanations
       - No blank lines
       - No extra text

       EXAMPLE INPUT: "Quel est la capitale de la France ?"
       EXAMPLE OUTPUT (exactly 7 lines):
       What is the capital of France?
       Paris est magnifique
       Paris is beautiful
       Connais-tu la tour Eiffel ?
       Do you know the Eiffel Tower?
       Quelle est la capitale de l'Espagne ?
       What is the capital of Spain?

       BEGIN NOW - OUTPUT EXACTLY 7 LINES:
       <end_of_turn>
       """
    }
    
    static func imageTranslationPrompt(
        sourceLang: String,
        targetLang: String
    ) -> String {
        """
        <bos><start_of_turn>user
        CRITICAL: You must output EXACTLY 7 lines. No more. No less.

        TASK: Identify object in image
        OUTPUT LANGUAGE: \(targetLang) for object name
        CONTEXT LANGUAGES: \(sourceLang) then \(targetLang) for each phrase

        OUTPUT FORMAT - EXACTLY 7 LINES IN THIS ORDER:
        LINE 1: Object name [\(targetLang) only]
        LINE 2: Context phrase 1 about object [\(sourceLang)]
        LINE 3: Context phrase 1 translated [\(targetLang)]
        LINE 4: Context phrase 2 about object [\(sourceLang)]
        LINE 5: Context phrase 2 translated [\(targetLang)]
        LINE 6: Context phrase 3 about object [\(sourceLang)]
        LINE 7: Context phrase 3 translated [\(targetLang)]

        FORBIDDEN:
        - No bullets (•, -, *)
        - No quotes (" or ')
        - No line numbers
        - No labels
        - No explanations
        - No blank lines
        - No extra text

        EXAMPLE (if image shows apple, English→Spanish):
        Manzana
        Do you like apples?
        ¿Te gustan las manzanas?
        The apple is red.
        La manzana es roja.
        Wash the apple before eating.
        Lava la manzana antes de comerla.

        BEGIN NOW - OUTPUT EXACTLY 7 LINES:
        <end_of_turn>
        """
    }
    
    static func chatAboutTranslationPrompt(
            sourceText: String,
            primaryTranslation: String,
            sourceLang: String,
            targetLang: String,
            userQuestion: String
        ) -> String {
            """
            SYSTEM:
            You are a meticulous multilingual translator and language tutor.
            Always reply in \(sourceLang) unless explicitly asked otherwise.

            CONTEXT:
            Original (\(sourceLang)): "\(sourceText)"
            Primary translation (\(targetLang)): "\(primaryTranslation)"

            TASK:
            \(userQuestion)

            INSTRUCTIONS:
            - Offer at least three alternative translations ranked by tone/register.
            - Explain subtle differences (≤ 2 sentences each).
            - If the user requests grammar or cultural notes, address them succinctly.
            """
        }
}

{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances #-}

module Core.CoreParser(parseTerm, parseFile, parseDef, pTerm, iName, idrisDef) where

import Core.TT

import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language
import qualified Text.ParserCombinators.Parsec.Token as PTok

import Debug.Trace

type TokenParser a = PTok.TokenParser a

idrisDef = haskellDef { 
              opStart = iOpStart,
              opLetter = iOpLetter,
              reservedOpNames = [":", "..", "=", "\\", "|", "<-", "->", "=>"],
              reservedNames = ["let", "in", "data", "Set", "if", "then", "else",
                               "do", "dsl", "import", 
                               "infix", "infixl", "infixr", "prefix",
                               "where", "forall", "syntax",
                               "using", "params", "namespace",
                               "Int", "Float", "Char", "String", "Ptr"]
           } 

iOpStart = oneOf ":!#$%&*+./<=>?@\\^|-~"
iOpLetter = oneOf ":!#$%&*+./<=>?@\\^|-~"
          <|> letter

lexer :: TokenParser a
lexer  = PTok.makeTokenParser idrisDef

whiteSpace= PTok.whiteSpace lexer
lexeme    = PTok.lexeme lexer
symbol    = PTok.symbol lexer
natural   = PTok.natural lexer
parens    = PTok.parens lexer
semi      = PTok.semi lexer
comma     = PTok.comma lexer
identifier= PTok.identifier lexer
reserved  = PTok.reserved lexer
operator  = PTok.operator lexer
reservedOp= PTok.reservedOp lexer
lchar = lexeme.char

type CParser a = GenParser Char a

parseFile = runParser pTestFile () "(input)"
parseDef = runParser pDef () "(input)"
parseTerm = runParser pTerm () "(input)"

pTestFile :: CParser a RProgram
pTestFile = do p <- many1 pDef ; eof
               return p

iName :: CParser a Name
iName = do x <- identifier
           return (UN [x])

pDef :: CParser a (Name, RDef)
pDef = try (do x <- iName; lchar ':'; ty <- pTerm
               lchar '='
               tm <- pTerm
               lchar ';'
               return (x, RFunction (RawFun ty tm)))
       <|> do x <- iName; lchar ':'; ty <- pTerm; lchar ';'
              return (x, RConst ty)
       <|> do (x, d) <- pData; lchar ';'
              return (x, RData d)

app :: CParser a (Raw -> Raw -> Raw)
app = do whiteSpace ; return RApp

arrow :: CParser a (Raw -> Raw -> Raw)
arrow = do symbol "->" ; return $ \s t -> RBind (MN 0 "X") (Pi s) t

pTerm :: CParser a Raw
pTerm = try (do chainl1 pNoApp app)
           <|> pNoApp

pNoApp :: CParser a Raw
pNoApp = try (chainr1 pExp arrow)
           <|> pExp
pExp :: CParser a Raw
pExp = do lchar '\\'; x <- iName; lchar ':'; ty <- pTerm
          symbol "=>";
          sc <- pTerm
          return (RBind x (Lam ty) sc)
       <|> try (do lchar '?'; x <- iName; lchar ':'; ty <- pTerm
                   lchar '.';
                   sc <- pTerm
                   return (RBind x (Hole ty) sc))
       <|> try (do lchar '('; 
                   x <- iName; lchar ':'; ty <- pTerm
                   lchar ')';
                   symbol "->";
                   sc <- pTerm
                   return (RBind x (Pi ty) sc))
       <|> try (do lchar '('; 
                   t <- pTerm
                   lchar ')'
                   return t)
       <|> try (do symbol "??";
                   x <- iName; lchar ':'; ty <- pTerm
                   lchar '=';
                   val <- pTerm
                   sc <- pTerm
                   return (RBind x (Guess ty val) sc))
       <|> try (do reserved "let"; 
                   x <- iName; lchar ':'; ty <- pTerm
                   lchar '=';
                   val <- pTerm
                   reserved "in";
                   sc <- pTerm
                   return (RBind x (Let ty val) sc))
       <|> try (do lchar '_'; 
                   x <- iName; lchar ':'; ty <- pTerm
                   lchar '.';
                   sc <- pTerm
                   return (RBind x (PVar ty) sc))
       <|> try (do reserved "Set"; i <- option 0 natural
                   return (RSet (fromInteger i)))
       <|> try (do x <- iName
                   return (Var x))

pData :: CParser a (Name, RawDatatype)
pData = do reserved "data"; x <- iName; lchar ':'; ty <- pTerm; reserved "where"
           cs <- many pConstructor
           return (x, RDatatype x ty cs)

pConstructor :: CParser a (Name, Raw)
pConstructor = do lchar '|'
                  c <- iName; lchar ':'; ty <- pTerm
                  return (c, ty)

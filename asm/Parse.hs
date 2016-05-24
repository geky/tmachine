module Parse where

import Prelude hiding (break, return)
import Control.Applicative
import Control.Monad
import Data.Char
import Data.Maybe
import Rule
import Result
import Pos


data Token
    = Label String
    | Pseudo String [Either String Int]
    | Ins String [Either String Int]
  deriving Show


symbol :: Rule Char String
symbol = rule $ \case
    c:_ | isSymbolPrefix c -> many1 (matchIf isSymbol)
    _                      -> reject
  where
    isSymbolPrefix c = isAlpha c || c == '_'
    isSymbol c = isSymbolPrefix c || isDigit c

ws :: Rule Char String
ws = many (matchIf isWs)
  where isWs c = c /= '\n' && isSpace c

digit :: Int -> Rule Char Int
digit base = fromIntegral . digitToInt <$> matchIf isBase
  where isBase c = isHexDigit c && digitToInt c < base

num :: Rule Char Int
num = do
    sign <- rule $ \case
        '-':_ -> accept 1 negate
        '+':_ -> accept 1 id
        _     -> accept 0 id
    base <- rule $ \case
        '0':b:_ | elem b "bB" -> accept 2 2
        '0':b:_ | elem b "oO" -> accept 2 8
        '0':b:_ | elem b "xX" -> accept 2 16
        _                     -> accept 0 10
    digits <- many1 (digit base)
    return $ sign (foldl1 (\a b -> a*base + b) digits)

string :: Char -> Rule Char String
string q = match q *> many (char q) <* match q
  where
    escape count base = do
        digits <- replicateM count (digit base)
        return $ chr (foldl1 (\a b -> a*base + b) digits)

    char q = rule $ \case
        '\\':'\\':_  -> accept 2 '\\'
        '\\':'\'':_  -> accept 2 '\''
        '\\':'\"':_  -> accept 2 '\"'
        '\\':'f':_   -> accept 2 '\f'
        '\\':'n':_   -> accept 2 '\n'
        '\\':'r':_   -> accept 2 '\r'
        '\\':'t':_   -> accept 2 '\t'
        '\\':'v':_   -> accept 2 '\v'
        '\\':'0':_   -> accept 2 '\0'
        '\\':'b':_   -> accept 2 () >> escape 8 2
        '\\':'o':_   -> accept 2 () >> escape 3 8
        '\\':'d':_   -> accept 2 () >> escape 3 10
        '\\':'x':_   -> accept 2 () >> escape 2 16
        '\\':_       -> reject
        '\n':_       -> reject
        c:_ | c /= q -> accept 1 c
        _            -> reject


label :: Rule Char Token
label = try (Label <$> symbol <* match ':' <* ws)

op :: Rule Char Token
op = op <* ws <*> delimited (arg <* ws) (match ',' <* ws)
  where 
    op = rule $ \case
        '.':_ -> Pseudo <$ match '.' <*> symbol
        _     -> Ins <$> symbol
    arg = rule $ \case
        c:_ | isSymbolPrefix c -> Left <$> symbol
        c:_ | isDigit c        -> Right <$> num
        _                      -> reject
      where isSymbolPrefix c = isAlpha c || c == '_'

term :: Rule Char ()
term = void $ optional comment *> match '\n'
  where comment = match ';' *> many (matchIf (/= '\n'))

line :: Rule Char [Token]
line = catMaybes <$ ws <*> mapM optional [label, op] <* term

parse :: FilePath -> String -> Result Msg [(Pos, Token)]
parse fp = expect fp . run parser . position fp
  where parser = concat <$> many (sequence <$> overM line)


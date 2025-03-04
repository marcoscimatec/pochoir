{-
 ----------------------------------------------------------------------------------
 -  Copyright (C) 2010-2011  Massachusetts Institute of Technology
 -  Copyright (C) 2010-2011  Yuan Tang <yuantang@csail.mit.edu>
 - 		                     Charles E. Leiserson <cel@mit.edu>
 - 	 
 -   This program is free software: you can redistribute it and/or modify
 -   it under the terms of the GNU General Public License as published by
 -   the Free Software Foundation, either version 3 of the License, or
 -   (at your option) any later version.
 -
 -   This program is distributed in the hope that it will be useful,
 -   but WITHOUT ANY WARRANTY; without even the implied warranty of
 -   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 -   GNU General Public License for more details.
 -
 -   You should have received a copy of the GNU General Public License
 -   along with this program.  If not, see <http://www.gnu.org/licenses/>.
 -
 -   Suggestsions:                  yuantang@csail.mit.edu
 -   Bugs:                          yuantang@csail.mit.edu
 -
 --------------------------------------------------------------------------------
 -}

module Main where

import Prelude hiding (catch)
import System.Cmd
import System.IO
import System.FilePath
import System.Environment
import System.Exit
import qualified Control.Exception as Control
import Data.List
import System.Directory 
import System.Cmd (rawSystem)
import Data.Char (isSpace)
import qualified Data.Map as Map
import Text.ParserCombinators.Parsec (runParser)

import PData
import PMainParser

main :: IO ()
main = do args <- getArgs
          whilst (null args) $ do
             printUsage
             exitFailure
          let (inFiles, inDirs, mode, debug, showFile, userArgs) 
                = parseArgs ([], [], PDefault, False, True, []) args
          whilst (mode == PHelp) $ do
             printOptions
             exitFailure

          ccEnvValue <- Control.catch (getEnv "CXX")
                         (\e -> do let err = show (e::Control.IOException)
                                   return err)

          let useGcc = if ccEnvValue == "g++"
                       then True
                       else False
          
          whilst (useGcc == True) $ do
             putStrLn ("CXX variable set to g++ detected. GNU compiler will be used.")

          whilst (mode /= PNoPP) $ do
             ppopp (mode, debug, showFile, userArgs, ccEnvValue) (zip inFiles inDirs)
          -- pass everything to icc after preprocessing and Pochoir optimization


          let cxxArgs = userArgs ++ ["-std=c++11"]
          if useGcc == False
             then putStrLn (icc ++ " " ++ intercalate " " cxxArgs)
             else putStrLn (gcc ++ " " ++ intercalate " " cxxArgs ++ " " ++ intercalate " " gccFlags)
          
          if useGcc == False
             then rawSystem icc cxxArgs
             else rawSystem gcc (cxxArgs ++ gccFlags)

          whilst (showFile == False) $ do
             let outFiles = map (rename "_pochoir") inFiles 
             removeFile $ intercalate " " outFiles

whilst :: Bool -> IO () -> IO ()
whilst True action = action
whilst False action = return () 

ppopp :: (PMode, Bool, Bool, [String], [Char]) -> [(String, String)] -> IO ()
ppopp (_, _, _, _, _) [] = return ()
ppopp (mode, debug, showFile, userArgs, compilerName) ((inFile, inDir):files) = 
    do putStrLn ("pochoir called with mode =" ++ show mode)
       pathLib <- Control.catch (getEnv "POCHOIR_LIB_PATH")
                         (\e -> do let err = show (e::Control.IOException)
                                   return "EnvError")

       let pochoirLibPath =  if pathLib == "EnvError"
            then do pochoirLibConfigPath
	    else do pathLib
	    	
       putStrLn ("POCHOIR_LIB_PATH: "++pochoirLibPath)
{-
       cilkStubPath <- catch (getEnv "CILK_HEADER_PATH")(\e -> return "EnvError")
       whilst (cilkStubPath == "EnvError") $ do
          putStrLn ("Environment variable CILK_HEADER_PATH is NOT set")
          exitFailure
       let envPath = ["-I" ++ cilkStubPath] ++ ["-I" ++ pochoirLibPath]
-}
       let envPath = ["-I" ++ pochoirLibPath]
       let iccPPFile = inDir ++ getPPFile inFile
       let iccPPArgs = if debug == False
             then iccPPFlags ++ envPath ++ [inFile]
             else iccDebugPPFlags ++ envPath ++ [inFile] 
       -- a pass of icc preprocessing
       if compilerName /= "g++"
          then putStrLn (icc ++ " " ++ intercalate " " iccPPArgs)
          else putStrLn (gcc ++ " " ++ intercalate " " (gccFlags ++ gccPPFlags ++ ["-o", getMidFile inFile] ++ envPath ++ [inFile]))

       -- a pass of pochoir compilation
       --let gccParams = gccFlags ++ envPath ++ [inFile]
       if compilerName /= "g++"
          then rawSystem icc iccPPArgs
          else rawSystem gcc (gccFlags ++ gccPPFlags ++ ["-o", getMidFile inFile] ++ envPath ++ [inFile])

       whilst (mode /= PDebug) $ do
           let outFile = rename "_pochoir" inFile
           inh <- openFile iccPPFile ReadMode
           outh <- openFile outFile WriteMode
           putStrLn ("pochoir " ++ show mode ++ " " ++ iccPPFile)
           pProcess mode inh outh
           hClose inh
           hClose outh
       whilst (mode == PDebug) $ do
           let midFile = getMidFile inFile
           let outFile = rename "_pochoir" midFile
           putStrLn ("mv " ++ midFile ++ " " ++ outFile)
           renameFile midFile outFile
       ppopp (mode, debug, showFile, userArgs, compilerName) files

getMidFile :: String -> String
getMidFile a  
    | isSuffixOf ".cpp" a || isSuffixOf ".cxx" a = take (length a - 4) a ++ ".i"
    | otherwise = a

rename :: String -> String -> String
rename pSuffix fname = name ++ pSuffix ++ ".cpp"
    where (name, suffix) = break ('.' ==) fname

getPPFile :: String -> String
getPPFile fname = name ++ ".i"
    where (name, suffix) = break ('.' ==) fname

{-
getObjFile :: String -> String -> [String]
getObjFile dir fname = ["-o"] ++ [dir++name]
    where (name, suffix) = break ('.' ==) fname 
-}

pInitState = ParserState { pMode = PCaching, pState = Unrelated, pMacro = Map.empty, pArray = Map.empty, pStencil = Map.empty, pShape = Map.empty, pRange = Map.empty, pKernel = Map.empty}

icc = "icpc"

iccFlags = ["-O3", "-DNDEBUG", "-std=c++0x", "-Wall", "-ipo"]

-- iccPPFlags = ["-P", "-C", "-DNCHECK_SHAPE", "-DNDEBUG", "-std=c++0x", "-Wall", "-Werror", "-ipo"]
iccPPFlags = ["-P", "-C", "-DNCHECK_SHAPE", "-DNDEBUG", "-std=c++0x", "-Wall", "-Werror"]

-- iccDebugFlags = ["-DDEBUG", "-O0", "-g3", "-std=c++0x", "-include", "cilk_stub.h"]
iccDebugFlags = ["-DDEBUG", "-O0", "-g3", "-std=c++0x"]

-- iccDebugPPFlags = ["-P", "-C", "-DCHECK_SHAPE", "-DDEBUG", "-g3", "-std=c++0x", "-include", "cilk_stub.h"]
iccDebugPPFlags = ["-P", "-C", "-DCHECK_SHAPE", "-DDEBUG", "-g3", "-std=c++0x"]

gcc = "g++"

gccPPFlags = ["-E","-DNCHECK_SHAPE", "-DNDEBUG"]

gccFlags = ["-fcilkplus", "-O3", "-std=c++11", "-Wall", "-Wno-unknown-pragmas", "-Wno-strict-aliasing","-lcilkrts", "-lm"]

pochoirLibConfigPath = "/home/marcos/Work/PochoirInstall/src/"

parseArgs :: ([String], [String], PMode, Bool, Bool, [String]) -> [String] -> ([String], [String], PMode, Bool, Bool, [String])
parseArgs (inFiles, inDirs, mode, debug, showFile, userArgs) aL 
    | elem "--help" aL =
        let l_mode = PHelp
            aL' = delete "--help" aL
        in  (inFiles, inDirs, l_mode, debug, showFile, aL')
    | elem "-h" aL =
        let l_mode = PHelp
            aL' = delete "-h" aL
        in  (inFiles, inDirs, l_mode, debug, showFile, aL')
    | elem "-auto-optimize" aL =
        let l_mode = PDefault
            aL' = delete "-auto-optimize" aL
        in  (inFiles, inDirs, l_mode, debug, showFile, aL')
    | elem "-split-caching" aL =
        let l_mode = PCaching
            aL' = delete "-split-caching" aL
        in  parseArgs (inFiles, inDirs, l_mode, debug, showFile, aL') aL'
    | elem "-split-c-pointer" aL =
        let l_mode = PCPointer
            aL' = delete "-split-c-pointer" aL
        in  parseArgs (inFiles, inDirs, l_mode, debug, showFile, aL') aL'
    | elem "-split-opt-pointer" aL =
        let l_mode = POptPointer
            aL' = delete "-split-opt-pointer" aL
        in  parseArgs (inFiles, inDirs, l_mode, debug, showFile, aL') aL'
    | elem "-split-pointer" aL =
        let l_mode = PPointer
            aL' = delete "-split-pointer" aL
        in  parseArgs (inFiles, inDirs, l_mode, debug, showFile, aL') aL'
    | elem "-split-macro-shadow" aL =
        let l_mode = PMacroShadow
            aL' = delete "-split-macro-shadow" aL
        in  parseArgs (inFiles, inDirs, l_mode, debug, showFile, aL') aL'
    | elem "-showFile" aL =
        let l_showFile = True
            aL' = delete "-showFile" aL
        in  parseArgs (inFiles, inDirs, mode, debug, l_showFile, aL') aL'
    | elem "-debug" aL =
        let l_debug = True 
            l_mode = PDebug
            aL' = delete "-debug" aL
        in  parseArgs (inFiles, inDirs, l_mode, l_debug, showFile, aL') aL'
    | null aL == False =
        let (l_files, l_dirs, l_mode, aL') = findCPP aL ([], [], mode, aL)
        in  (l_files, l_dirs, l_mode, debug, showFile, aL')
    | otherwise = 
        let l_mode = PNoPP
        in  (inFiles, inDirs, l_mode, debug, showFile, aL)

findCPP :: [String] -> ([String], [String], PMode, [String]) -> ([String], [String], PMode, [String])
findCPP [] (l_files, l_dirs, l_mode, l_al) = 
    let l_mode' = 
            if null l_files == True || null l_dirs == True then PNoPP else l_mode
    in  (l_files, l_dirs, l_mode', l_al)
findCPP (a:as) (l_files, l_dirs, l_mode, l_al)
    | isSuffixOf ".cpp" a || isSuffixOf ".cxx" a = 
        let l_file = drop (1 + (pLast $ findIndices (== '/') a)) a
            l_dir  = take (1 + (pLast $ findIndices (== '/') a)) a
            l_files' = l_files ++ [l_file]
            l_dirs'  = l_dirs ++ [l_dir]
            pLast [] = -1
            pLast aL@(a:as) = last aL
            l_pochoir_file = rename "_pochoir" l_file 
            (prefix, suffix) = break (a == ) l_al
            l_al' = prefix ++ [l_pochoir_file] ++ tail suffix
        in  findCPP as (l_files', l_dirs', l_mode, l_al')
    | otherwise = findCPP as (l_files, l_dirs, l_mode, l_al)

printUsage :: IO ()
printUsage =
    do putStrLn ("Usage: pochoir [OPTION] [filename]")
       putStrLn ("Try `pochoir --help' for more options.")

printOptions :: IO ()
printOptions = 
    do putStrLn ("Usage: pochoir [OPTION] [filename]")
       putStrLn ("Run the Pochoir stencil compiler on [filename].")
       putStrLn ("-auto-optimize : " ++ breakline ++ "Let the Pochoir compiler automatically choose the best optimizing level for you! (default)")
       putStrLn ("-split-macro-shadow $filename : " ++ breakline ++ 
               "using macro tricks to split the interior and boundary regions")
       putStrLn ("-split-pointer $filename : " ++ breakline ++ 
               "Default Mode : split the interior and boundary region, and using C-style pointer to optimize the base case")

pProcess :: PMode -> Handle -> Handle -> IO ()
pProcess mode inh outh = 
    do ls <- hGetContents inh
       let pRevInitState = pInitState { pMode = mode }
       case runParser pParser pRevInitState "" $ stripWhite ls of
           Left err -> print err
           Right str -> hPutStrLn outh str



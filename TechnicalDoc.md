# Ashta Chemma

Ashtam Chemma normally has a 5x5 square board and four players, but one can also increase the number of squares depending on the number of players to any odd number squared (for example, 11x11). Assuming the size of the board is NxN (with N being odd), then each player will have N-1 pawns.

### Game loop
The game is controlled by throwing four cowry shells and counting how many are 'as it is' versus those that land 'inverted': if all four shells land inverted it is called "ashta" and if all land as it is then it is called a "chamma".

## File Paths
- `assets/`
  - `board.png`
  - `pawn.png`
- `board/`
  - `data/`
    - `board_layout_standard.tres`
    - `Temp.gd`
  - `Board.gd`
  - `BoardData.gd`
  - `Board.tscn`
- `game_manager/`
  - `GameManager.gd`
  - `GameManager.tscn`
- `pawn/`
  - `Pawn.gd`
  - `Pawn.tscn`
- `tools/`
  - `BoardDataGenerator.gd`
  - `GeneratorTool.tscn`
- `project.godot`
- `MainGame.tscn`
- `README.md`
- `TechnicalDoc.md`


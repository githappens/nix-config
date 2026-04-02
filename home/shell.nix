# Zsh config — GPG/SSH agent wiring, git aliases, shell utilities.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gum
    neovim
  ];

  programs.zsh = {
    enable = true;

    shellAliases = {
      # gpg
      kill-gpg-agent = ''gpg-connect-agent "scd killscd" /bye'';

      # quick zshrc editing (for tweaks outside home-manager)
      editme = "nvim ~/.zshrc";
      refreshme = "source ~/.zshrc";

      # git
      g = "git";
      gl = "git log";
      gco = "git checkout";
      gcm = "git commit -m";
      gs = "git status";
      gps = "git push";
      gpl = "git pull";
      gres = "git restore";
      gsu = "git submodule update --init --recursive";
      migratetolfs = "git lfs migrate import --no-rewrite";
      addbdcommitconfig = ''git config user.name "Bence Kovács"; git config user.email "148470497+BD-Bence@users.noreply.github.com"'';

      # audio
      rescanau = "killall -9 AudioComponentRegistrar; auval -al";
    };

    initExtra = ''
      # GPG-agent as SSH agent
      export GPG_TTY=$(tty)
      export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
      gpgconf --launch gpg-agent
      gpg-connect-agent updatestartuptty /bye 2>/dev/null

      function gfogco() {
          git fetch origin && git checkout $1 && git submodule update --init --recursive
      }

      function fixlfsrefs() {
          git rm --cached -r .
          git reset --hard
          git rm .gitattributes
          git reset .
          git checkout .
      }

      function shallowclone() {
          if [[ "''${1-}" =~ ^-*h(elp)?$ ]]; then
              echo "Usage: $funcstack[1] repo-url branch-or-tag depth

      Shortcut for creating a shallow clone of a repo from a specific branch or tag."
              return 0
          fi
          repo=$1
          branch=$2
          nCommits=$3
          git clone -b $2 --single-branch --depth $3 $1
      }

      function cds() {
          IFS=$'\n' folders=($(ls -d */ 2>/dev/null | sed 's#/##'))
          unset IFS
          if [ ''${#folders[@]} -eq 0 ]; then
              echo "No subdirectories found."
              return
          fi
          selected_folder=$(printf "%s\n" "''${folders[@]}" | gum filter)
          cd "$selected_folder"
      }

      function cdr() {
          IFS=$'\n' folders=($(ls -d */ 2>/dev/null | sed 's#/##'))
          unset IFS
          if [ ''${#folders[@]} -eq 0 ]; then
              echo "No subdirectories found."
              return
          fi
          folders=("./" "../" "''${folders[@]}")
          selected_folder=$(printf "%s\n" "''${folders[@]}" | gum filter)
          if [[ "$selected_folder" == "./" ]]; then
              return
          elif [[ "$selected_folder" == "../" ]]; then
              cd .. && cdr
          else
              cd "$selected_folder" && cdr
          fi
      }

      function createscript() {
          if [[ "''${1-}" =~ ^-*h(elp)?$ ]]; then
              echo "Usage: $funcstack[1] script-name script-folder(optional)

      Generates a new shell script from the template.
      Script folder can be passed in as second argument optionally."
              return 0
          fi
          scriptDir=''${2:-"$HOME/scripts"}
          cat "$HOME/scripts/.scripttemplate" > "$scriptDir/$1.sh"
          chmod 755 "$scriptDir/$1.sh"
          nvim "$scriptDir/$1.sh"
      }

      # Add scripts folder to PATH
      PATH="$HOME/scripts:$PATH"
    '';
  };
}

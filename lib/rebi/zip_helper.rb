module Rebi
  class ZipHelper

    include Rebi::Log

    def initialize
      raise Rebi::Error::NoGit.new("Not a git repository") unless git?
    end

    def git?
      `git status`
      $?.success?
    end

    def ls_files
      `git ls-files`.split("\n")
    end

    def raw_zip_archive opts={}
      tmp_file = Tempfile.new("git_archive")
      commit_id = opts[:staged] ? `git write-tree`.chomp : "HEAD"
      system "git archive --format=zip #{commit_id} > #{tmp_file.path}"
      return tmp_file
    end

    def version_label
      `git describe --always --abbrev=8`.chomp
    end

    def message
      `git log --oneline -1`.chomp.split(" ")[1..-1].join(" ")[0..190]
    end

    # Create zip archivement
    def gen env_conf,opts={}
      log("Creating zip archivement", env_conf.name)
      start = Time.now
      ebextensions = env_conf.ebextensions
      files = ls_files
      tmp_file = raw_zip_archive opts
      tmp_folder = Dir.mktmpdir
      Zip::File.open(tmp_file) do |z|
        ebextensions.each do |ex_folder|
          Dir.glob("#{ex_folder}/*.config") do |fname|
            z.remove_folder ex_folder unless ex_folder == ".ebextension"
            next unless (File.file?(fname) && files.include?(fname))
            next unless y = YAML::load(ErbHelper.new(File.read(fname), env_conf).result)
            basename = File.basename(fname)
            target = ".ebextensions/#{basename}"
            tmp_yaml = "#{tmp_folder}/#{basename}"
            File.open(tmp_yaml, 'w') do |f|
              f.write y.to_yaml
            end
            z.remove target if z.find_entry target
            z.add target, tmp_yaml
          end
        end

        dockerrun_file = env_conf.dockerrun || "Dockerrun.aws.json"

        if File.exists?(dockerrun_file)
          dockerrun = JSON.parse ErbHelper.new(File.read(dockerrun_file), env_conf).result
          tmp_dockerrun = "#{tmp_folder}/Dockerrun.aws.json"
          File.open(tmp_dockerrun, 'w') do |f|
            f.write dockerrun.to_json
          end
          z.remove env_conf.dockerrun if z.find_entry env_conf.dockerrun
          z.remove "Dockerrun.aws.json" if z.find_entry "Dockerrun.aws.json"
          z.add "Dockerrun.aws.json", tmp_dockerrun
        end

      end
      FileUtils.rm_rf tmp_folder
      log("Zip was created in: #{Time.now - start}s", env_conf.name)
      return {
        label: Time.now.strftime("app_#{env_conf.name}_#{version_label}_%Y%m%d_%H%M%S"),
        file: File.open(tmp_file.path),
        message: message,
      }
    end

  end
end

module Zip
  class File
    def remove_folder fname
      if folder = find_entry(fname)
        remove folder if folder.directory?
      end
      glob("#{fname}/**/*").each do |f|
        remove f
      end
    end
  end
end

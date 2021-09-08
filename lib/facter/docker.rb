# frozen_string_literal: true

require 'facter'
require 'json'

Facter.add(:docker_systemroot) do
  confine osfamily: :windows
  setcode do
    Puppet::Util.get_env('SystemRoot')
  end
end

Facter.add(:docker_program_files_path) do
  confine osfamily: :windows
  setcode do
    Puppet::Util.get_env('ProgramFiles')
  end
end

Facter.add(:docker_program_data_path) do
  confine osfamily: :windows
  setcode do
    Puppet::Util.get_env('ProgramData')
  end
end

Facter.add(:docker_user_temp_path) do
  confine osfamily: :windows
  setcode do
    Puppet::Util.get_env('TEMP')
  end
end

docker_command = if Facter.value(:kernel) == 'windows'
                   'powershell -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -c docker'
                 else
                   'docker'
                 end

def interfaces
  Facter.value(:interfaces).split(',')
end

Facter.add(:docker_client_version) do
  setcode do
    docker_version = Facter.value(:docker_version)
    if docker_version
      if !docker_version['Client'].nil?
        docker_version['Client']['Version']
      else
        docker_version['Version']
      end
    end
  end
end

Facter.add(:docker_server_version) do
  setcode do
    docker_version = Facter.value(:docker_version)
    if docker_version && !docker_version['Server'].nil? && docker_version['Server'].is_a?(Hash)
      docker_version['Server']['Version']
    else
      nil
    end
  end
end

Facter.add(:docker_version) do
  setcode do
    if Facter::Core::Execution.which('docker')
      value = Facter::Core::Execution.execute(
        "#{docker_command} version --format '{{json .}}'", time_limit: 90
      )
      val = JSON.parse(value)
    end
    val
  end
end

Facter.add(:docker_worker_join_token) do
  setcode do
    if Facter::Util::Resolution.which('docker')
      val = Facter::Util::Resolution.execute(
        "#{docker_command} swarm join-token worker -q",
      )
    end
    val
  end
end

Facter.add(:docker_manager_join_token) do
  setcode do
    if Facter::Util::Resolution.which('docker')
      val = Facter::Util::Resolution.execute(
        "#{docker_command} swarm join-token manager -q",
      )
    end
    val
  end
end

Facter.add(:docker) do
  setcode do
    docker_version = Facter.value(:docker_client_version)
    if docker_version&.match?(%r{1[0-9][0-2]?[.]\w+})
      if Facter::Core::Execution.which('docker')
        docker_json_str = Facter::Core::Execution.execute(
          "#{docker_command} info --format '{{json .}}'", time_limit: 90
        )
        begin
          docker = JSON.parse(docker_json_str)
          docker['network'] = {}

          docker['network']['managed_interfaces'] = {}
          network_list = Facter::Core::Execution.execute("#{docker_command} network ls | tail -n +2", time_limit: 90)
          docker_network_names = []
          network_list.each_line { |line| docker_network_names.push line.split[1] }
          docker_network_ids = []
          network_list.each_line { |line| docker_network_ids.push line.split[0] }
          docker_network_names.each do |network|
            inspect = JSON.parse(Facter::Core::Execution.execute("#{docker_command} network inspect #{network}", time_limit: 90))
            docker['network'][network] = inspect[0]
            network_id = docker['network'][network]['Id'][0..11]
            interfaces.each do |iface|
              docker['network']['managed_interfaces'][iface] = network if %r{#{network_id}}.match?(iface)
            end
          end
          docker
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end

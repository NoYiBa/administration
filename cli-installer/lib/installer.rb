#
# owncloud-admin - the owncloud administration tool
#
# Copyright (C) 2011 Cornelius Schumacher <schumacher@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

class Installer

  attr_accessor :server, :ftp_user, :ftp_password, :skip_download, :root_helper,
      :admin_user, :admin_password
  
  def initialize settings
    @settings = settings
  end

  def self.server_types
    [ "local", "ftp" ]
  end
  
  def install server_type
    if !skip_download
      source = {
        :server => "owncloud.org",
        :path => "/releases/",
        :file => "owncloud-latest.tar.bz2"
      }

      local_source = @settings.tmp_dir + source[:file]

      puts "Downloading owncloud source archive..."
      Net::HTTP.start( source[:server] ) do |http|
        response = http.get( source[:path] + source[:file] )
        open( local_source, "wb") do |file|
          file.write response.body
        end
      end

      puts "Extracting archive..."
      system "cd #{@settings.tmp_dir}; tar xjf #{source[:file]}"
    end

    @source_dir = @settings.tmp_dir + "owncloud"

    write_admin_config
    
    if server_type == "local"
      install_local
    elsif server_type == "ftp"
      install_ftp
    else
      STDERR.puts "Unsupported server type: #{server_type}"
      exit 1
    end
  end

  def write_admin_config
    if !@admin_password
      STDERR.puts "Initial admin password is required"
      exit 1
    end
    if !@admin_user
      @admin_user = ENV["USER"]
    end

    config = <<EOF
<?php
$AUTOCONFIG = array(
  "dbtype" => 'sqlite',
  "directory" => OC::$SERVERROOT."/data",
  "adminlogin" => "#{@admin_user}",
  "adminpass" => "#{@admin_password}"
);
?>
EOF

    config_file = @source_dir + "/config/autoconfig.php"

    File.open config_file, "w" do |file|
      file.print config
    end
  end

  def install_local
    # Requirements for ownCloud to run:
    # * packages installed: apache2, apache2-mod_php5, php5-json, php5-dom,
    #   php5-sqlite, php5-mbstring php5-ctype
    # * apache2 running
    
    puts "Installing owncloud to local web server..."
    http_docs_dir = "/srv/www/htdocs/"
    
    system "#{@root_helper} \"cp -r #{@source_dir} #{http_docs_dir}\""
    system "#{@root_helper} \"chown -R wwwrun:www #{http_docs_dir}owncloud\""
  end
  
  def install_ftp
    puts "Installing owncloud to remote web server via FTP..."

    assert_options [ :server, :ftp_user, :ftp_password ]

    ftp = Net::FTP.new( server )
    ftp.passive = true
    puts "  Logging in..."
    ftp.login ftp_user, ftp_password

    puts "  Finding installation directory..."
    install_dir = ""
    [ "httpdocs" ].each do |d|
      dir = try_ftp_cd ftp, d
      if dir
        install_dir = dir
        break
      end
    end
    print "  Installing to dir '#{install_dir}'..."

    upload_dir_ftp ftp, @source_dir, "owncloud"
    puts ""
    
    puts "  Closing..."
    ftp.close
  end
  
  private

  def upload_dir_ftp ftp, source_path, target_path
    puts ""
    print "  Uploading dir #{target_path}"
    assert_ftp_directory ftp, target_path
    if target_path == "owncloud/data"
# FIXME: When ownCloud allows it set permissions so that it works
#      ftp.sendcmd("SITE CHMOD 0772 #{target_path}")
      ftp.sendcmd("SITE CHMOD 0770 #{target_path}")
    end
    Dir.entries( source_path ).each do |entry|
      next if entry =~ /^\.\.?$/
      
      source_file = source_path + "/" + entry
      target_file = target_path + "/" + entry
      if File.directory? source_file
        upload_dir_ftp ftp, source_file, target_path + "/" + entry
      else      
        print "."
        ftp.putbinaryfile source_file, target_file
      end
    end
  end
  
  def assert_ftp_directory ftp, dir
    begin
      ftp.mkdir dir
    rescue Net::FTPPermError => e
      if e.message !~ /File exists/
        raise e
      end
    end
  end
  
  def try_ftp_cd ftp, dir
    begin
      ftp.chdir dir
      return dir
    rescue Net::FTPPermError => e
      return nil
    end
  end
  
  def assert_options options
    @errors = Array.new
    options.each do |option|
      value = send option
      if value.nil?
        @errors.push "Missing option: #{option}"
      end
    end
    if !@errors.empty?
      STDERR.puts @errors.join( "\n" )
      exit 1
    end
  end
  
end

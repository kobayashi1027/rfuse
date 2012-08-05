require 'spec_helper'
require 'pathname'

describe RFuse::Fuse do
   
    let(:dir_stat) { RFuse::Stat.directory(0444) }
    let(:file_stat) { RFuse::Stat.file(0444) }
    let!(:mockfs) { m = mock("fuse"); m.stub(:getattr).and_return(nil); m }
    let(:mountpoint) { tempmount() }

    context "mount options" do
        it "should handle -h" do
            fuse = RFuse::FuseDelegator.new(mockfs,mountpoint,"-h")
            fuse.mounted?.should be_false
            lambda { fuse.loop }.should raise_error(RFuse::Error)
        end

        it "should behave sensibly for bad mountpoint" do
            fuse = RFuse::FuseDelegator.new(mockfs,"bad/mount/point")
            fuse.mounted?.should be_false
            lambda { fuse.loop }.should raise_error(RFuse::Error)
        end

        it "should behave sensibly for bad options" do
            fuse = RFuse::FuseDelegator.new(mockfs,mountpoint,"-eviloption") 
            fuse.mounted?.should be_false
            lambda { fuse.loop }.should raise_error(RFuse::Error)
        end
       
        it "should handle a Pathname as a mountpoint" do
            fuse = RFuse::FuseDelegator.new(mockfs,Pathname.new(mountpoint))
            fuse.mounted?.should be_true
            fuse.unmount()
        end
    end

    context "links" do
        it "should create and resolve symbolic links"

        it "should create and resolve hard links"

    end

    context "directories" do
        it "should make directories" do

            mockfs.stub(:getattr).and_return(nil)
            mockfs.stub(:getattr).with(anything(),"/aDirectory").and_return(nil,dir_stat)
            mockfs.should_receive(:mkdir).with(anything(),"/aDirectory",anything())

            with_fuse(mountpoint,mockfs) do
                Dir.mkdir("#{mountpoint}/aDirectory")
            end
        end

        it "should list directories" do

            mockfs.should_receive(:readdir) do | ctx, path, filler,offset,ffi | 
                filler.push("hello",nil,0)
                filler.push("world",nil,0)
            end

            with_fuse(mountpoint,mockfs) do
                entries = Dir.entries(mountpoint)
                entries.size.should == 2
                entries.should include("hello")
                entries.should include("world")
            end
        end
    end

    context "permissions" do
        it "should process chmod" do
            mockfs.stub(:getattr).with(anything(),"/myPerms").and_return(file_stat)

            mockfs.should_receive(:chmod).with(anything(),"/myPerms",file_mode(0644))

            with_fuse(mountpoint,mockfs) do
                File.chmod(0644,"#{mountpoint}/myPerms").should == 1
            end
        end
    end

    context "timestamps" do

        it "should support stat with subsecond resolution" do
           begin
               atime = Time.now() + 60
               sleep(0.001)
           end until atime.usec != 0

           begin
               mtime = Time.now() + 600
               sleep(0.001)
           end until mtime.usec != 0

           begin
                ctime = Time.now() + 3600
                sleep(0.001)
           end until ctime.usec != 0

           file_stat.atime = atime
           file_stat.mtime = mtime
           file_stat.ctime = ctime


           # ruby can't set file times with ns res, o we are limited to usecs
           mockfs.stub(:getattr).with(anything(),"/nanos").and_return(file_stat)

           with_fuse(mountpoint,mockfs) do
               stat = File.stat("#{mountpoint}/nanos")
               stat.atime.should == atime
               stat.ctime.should == ctime
               stat.mtime.should == mtime
           end
        end

        it "should set file access and modification times" do

            atime = Time.now()
            mtime = atime + 1

            mockfs.stub(:getattr).with(anything(),"/times").and_return(file_stat)
            mockfs.should_receive(:utime).with(anything(),"/times",atime.to_i,mtime.to_i)

            with_fuse(mountpoint,mockfs) do
                File.utime(atime,mtime,"#{mountpoint}/times").should == 1
            end
        end

    end

    context "file io" do

        it "should create files" do

           mockfs.stub(:getattr).with(anything(),"/newfile").and_return(nil,file_stat)
           mockfs.should_receive(:mknod).with(anything(),"/newfile",file_mode(0644),0,0)
         
           with_fuse(mountpoint,mockfs) do
                File.open("#{mountpoint}/newfile","w",0644) { |f| }
           end
        end

        # ruby doesn't seem to have a native method to create these
        # maybe try ruby-mkfifo
        it "should create special device files"

        it "should read files" do

            file_stat.size = 11
            mockfs.stub(:getattr) { | ctx, path|
                case path 
                when "/test"
                    file_stat
                else
                    raise Errno::ENOENT 
                end

            }
            
            reads = 0
            mockfs.stub(:read) { |ctx,path,size,offset,ffi|
                reads += 2
                "hello world"[offset,reads]
            }

            with_fuse(mountpoint,mockfs) do
                File.open("#{mountpoint}/test") do |f|
                    val = f.gets
                    val.should == "hello world"
                end
            end
        end
    end
end

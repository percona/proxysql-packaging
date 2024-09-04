%define        __spec_install_post %{nil}
%define          debug_package %{nil}
%define        __os_install_post %{_dbpath}/brp-compress

%{!?with_systemd:%global systemd 0}
%{?el7:          %global systemd 1}
%{?el8:          %global systemd 1}
%{?el9:          %global systemd 1}

Summary: A high-performance MySQL proxy
Name: proxysql2
Version: @@VERSION@@
Release: @@RELEASE@@
License: GPL+
Group: Development/Tools
Source0 : proxysql2-%{version}.tar.gz
Source1 : proxysql-admin
Source2 : proxysql-admin.cnf
Source3 : config.toml
Source4 : percona-scheduler-admin
Source5 : LICENSE
Source6 : proxysql-logrotate
Source7 : proxysql-status
Source8 : proxysql-admin-common
Source9 : proxysql-login-file
Source10 : pxc_scheduler_handler
Source11 : proxysql-common
URL: http://www.proxysql.com/
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
Requires: logrotate procps
Requires(pre): shadow-utils
Requires(pre): /usr/sbin/useradd, /usr/bin/getent, /usr/bin/ps
Requires(postun): /usr/sbin/userdel
%if 0%{?systemd}
BuildRequires:  systemd
BuildRequires:  pkgconfig(systemd)
Requires(post):   systemd
Requires(preun):  systemd
Requires(postun): systemd
%else
Requires(post):   /sbin/chkconfig
Requires(preun):  /sbin/chkconfig
Requires(preun):  /sbin/service
%endif


%description
%{summary}

%prep
%setup -q
install %SOURCE5 %{name}-%{version}

%build
sed -i -e 's/c++11/c++0x/' lib/Makefile
sed -i -e 's/c++11/c++0x/' src/Makefile
make clean
make
mv proxysql-admin-tool/proxysql-admin.cnf proxysql-admin.cnf.in

%install
install -d %{buildroot}/%{_bindir}
install -d  %{buildroot}/%{_sysconfdir}
install -d %{buildroot}/%{_datarootdir}/proxysql/etc
install -d  %{buildroot}/%{_sysconfdir}/init.d
install -d  %{buildroot}/%{_sysconfdir}/logrotate.d
install -m 0755 src/proxysql %{buildroot}/%{_bindir}
install -m 0640 etc/proxysql.cnf %{buildroot}/%{_sysconfdir}
install -m 0640 proxysql-admin.cnf.in %{buildroot}/%{_datarootdir}/proxysql/etc/
install -m 0640 %SOURCE3 %{buildroot}/%{_sysconfdir}
%if 0%{?systemd}
  install -m 0755 -d %{buildroot}/%{_unitdir}
  install -m 0644 systemd/system/proxysql.service %{buildroot}/%{_unitdir}/proxysql.service
%else
  install -m 0755 -d %{buildroot}/etc/rc.d/init.d
  install -m 0755 etc/init.d/proxysql %{buildroot}/%{_sysconfdir}/init.d
%endif

install -d %{buildroot}/var/lib/proxysql
install -d %{buildroot}/var/run/proxysql
install -d %{buildroot}/var/run/pxc_scheduler_handler
install -m 0755 %SOURCE1 %{buildroot}/%{_bindir}/proxysql-admin
install -m 0755 %SOURCE8 %{buildroot}/%{_bindir}/proxysql-admin-common
install -m 0755 %SOURCE11 %{buildroot}/%{_bindir}/proxysql-common
install -m 0755 %SOURCE9 %{buildroot}/%{_bindir}/proxysql-login-file
install -m 0755 tools/proxysql_galera_checker.sh %{buildroot}/%{_bindir}/proxysql_galera_checker
install -m 0755 tools/proxysql_galera_writer.pl %{buildroot}/%{_bindir}/proxysql_galera_writer
install -m 0755 %SOURCE7 %{buildroot}/%{_bindir}/proxysql-status
install -m 0644 %SOURCE6 %{buildroot}/%{_sysconfdir}/logrotate.d/proxysql-logrotate
install -m 0755 %SOURCE10 %{buildroot}/%{_bindir}/pxc_scheduler_handler
install -m 0755 %SOURCE4 %{buildroot}/%{_bindir}/percona-scheduler-admin

%clean
rm -rf %{buildroot}


%pre
getent group proxysql >/dev/null || groupadd -r proxysql
useradd -r -g proxysql -r -d /var/lib/proxysql -s /bin/false \
    -c "ProxySQL" proxysql >/dev/null 2>&1 || :

STATUS_FILE=/tmp/PROXYSQL_UPGRADE_MARKER
EXIST=$(ps wwaux | grep /usr/bin/proxysql | grep -v grep | wc -l )
if [ "$EXIST" -gt "0" ]; then
    echo "SERVER_TO_START=1" >> $STATUS_FILE
else
    echo "SERVER_TO_START=0" >> $STATUS_FILE
fi



%post

case "$1" in
    1)
        %if 0%{?systemd}
            %systemd_post proxysql.service
            if [ $1 == 1 ]; then
                /usr/bin/systemctl enable proxysql >/dev/null 2>&1 || :
            fi
        %else
            if [ $1 == 1 ]; then
                /sbin/chkconfig --add proxysql
            fi
        %endif
    ;;
esac

if [ ! -f /etc/proxysql-admin.cnf ]; then
    cp /usr/share/proxysql/etc/proxysql-admin.cnf.in /etc/proxysql-admin.cnf
    chmod 0640 /etc/proxysql-admin.cnf
    chown root:proxysql /etc/proxysql-admin.cnf
fi

EXISTING_FILE_PROPERTIES_COUNT=$(grep "export .*=" /etc/proxysql-admin.cnf | awk -F '[ =]' '{print $2}' | sort -u | wc -l)
NEW_FILE_PROPERTIES_COUNT=$(grep "export .*=" /usr/share/proxysql/etc/proxysql-admin.cnf.in | awk -F '[ =]' '{print $2}' | sort -u | wc -l)

if [ "$EXISTING_FILE_PROPERTIES_COUNT" -ne "$NEW_FILE_PROPERTIES_COUNT" ]; then
    echo "NOTE: /usr/share/proxysql/etc/proxysql-admin.cnf.in does not match the configuration of existing /etc/proxysql-admin.cnf. Please review the two files and ensure that the configuration in /etc/proxysql-admin.cnf is updated accordingly."
fi
exit 0

%postun
%if 0%{?systemd}
  %systemd_postun_with_restart proxysql.service
%else
  if [ $1 -ge 1 ]; then
    /sbin/service proxysql restart >/dev/null 2>&1 || :
  fi
%endif

find /usr/share/proxysql -type d -empty -delete
exit 0

%preun
if [ "$1" = "0" ]; then
%if 0%{?systemd}
    /bin/systemctl disable proxysql.service >/dev/null 2>&1 || :
    /bin/systemctl stop proxysql.service > /dev/null 2>&1 || :
%else
    /sbin/service proxysql stop >/dev/null 2>&1 || :
    /sbin/chkconfig --del proxysql
%endif
fi
exit 0

%files
%defattr(-,root,root,-)
%{_bindir}/proxysql_galera_checker
%{_bindir}/proxysql_galera_writer
%{_bindir}/proxysql-admin
%{_bindir}/proxysql-admin-common
%{_bindir}/proxysql-common
%{_bindir}/proxysql-login-file
%{_bindir}/proxysql-status
%{_bindir}/pxc_scheduler_handler
%{_bindir}/percona-scheduler-admin
%{_bindir}/proxysql
%if 0%{?systemd}
%{_unitdir}/proxysql.service
%else
%{_sysconfdir}/init.d/proxysql
%endif
%{_datarootdir}/proxysql/etc/proxysql-admin.cnf.in
%config(noreplace) %{_sysconfdir}/logrotate.d/proxysql-logrotate
%defattr(-,proxysql,proxysql,-)
/var/lib/proxysql
/var/run/proxysql
/var/run/pxc_scheduler_handler
%defattr(644,root,proxysql,-)
%config(noreplace) %{_sysconfdir}/config.toml
%defattr(-,root,proxysql,-)
%config(noreplace) %{_sysconfdir}/proxysql.cnf
%doc LICENSE

%changelog
* Wed Dec 13 2023 Muhammad Aqeel <muhammad.aqeel@percona.com> 2.3.2-1.3
- PSQLADM-164 Installing proxysql-admin.cnf.in in installation directory

* Tue Jun 07 2022 Vadim Yalovets <vadim.yalovets@percona.com> 2.3.2-1.2
- PSQLADM-389 Missing files in the ProxySQL package

* Wed May 18 2022 Vadim Yalovets <vadim.yalovets@percona.com> 2.3.2-1.1
- PSQLADM-322 Add pxc_scheduler_handler into ProxySQL package

* Wed Aug 09 2017  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.3.9-1.1
- added proxysql-logrotate

* Wed Sep 21 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.3-1.0.1
- added proxysql-admin tool

* Fri Jul 15 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.0-1.0.1
- First build of proxysql for Percona.

ARG BUILDDEPS="sudo dash argon2"
ARG MAKEDIRS="/environment"
ARG EXECUTABLES="/usr/bin/sudo /usr/bin/dash /usr/bin/argon2"

FROM huggla/busybox:20180921-edge as init

FROM huggla/build as build

FROM scratch as final-image

COPY --from=build /imagefs /

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/start" \
    VAR_LINUX_USER="root" \
    VAR_FINAL_COMMAND="pause" \
    VAR_ARGON2_PARAMS="-r" \
    VAR_SALT_FILE="/proc/sys/kernel/hostname" \
    HISTFILE="/dev/null"

ONBUILD COPY --from=build /imagefs /

#ONBUILD RUN rm -rf /lib/apk /etc/apk \
ONBUILD RUN chmod u+s /usr/local/bin/sudo \
         && find /usr/local/bin/* ! -name sudo | xargs chmod o-rwx \
         && chmod go= /environment /bin /sbin /usr/bin /usr/sbin /etc/sudoers \
         && chmod -R o= /start /tmp \
         && chmod u=rx,go= /start/stage1 /start/stage2 \
         && chmod u=rw,go= /etc/sudoers.d/docker* \
         && chmod -R g=r,o= /stop \
         && chmod g=rx /stop /stop/functions \
         && chmod u=rwx,g=rx /stop/stage1

ONBUILD USER starter

ONBUILD CMD ["sudo","start"]

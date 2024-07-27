# enable script
# chmod +x clean.sh

#!/bin/bash
find . -name 'obj' -type d -exec rm -rv {} + ; find . -name 'bin' -type d -exec rm -rv {} + ;

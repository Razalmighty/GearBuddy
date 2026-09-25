local failed = false;
for index = 1,#arg do
    local chunk,message = loadfile(arg[index]);
    if chunk == nil then
        io.stderr:write(arg[index] .. ": " .. tostring(message) .. "\n");
        failed = true;
    end
end
if failed then
    os.exit(1);
end
print("Lua syntax load passed for " .. tostring(#arg) .. " files.");
